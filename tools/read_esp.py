#!/usr/bin/env python3
"""Read OBS Lite sensor data directly from ESP32 via USB serial (COBS/PacketSerial)."""

import serial
import struct
import sys
import time

PORT = "/dev/tty.usbserial-310"
BAUD = 115200

def cobs_decode(data):
    output = bytearray()
    i = 0
    while i < len(data):
        code = data[i]
        if code == 0:
            break
        i += 1
        for j in range(1, code):
            if i >= len(data):
                return None
            output.append(data[i])
            i += 1
        if code < 0xFF and i < len(data):
            output.append(0)
    if output and output[-1] == 0:
        output = output[:-1]
    return bytes(output)

def decode_varint(data, pos):
    result = 0
    shift = 0
    while pos < len(data):
        b = data[pos]
        result |= (b & 0x7F) << shift
        pos += 1
        if (b & 0x80) == 0:
            return result, pos
        shift += 7
    return result, pos

def parse_distance_measurement(data):
    """Parse DistanceMeasurement: field 1=source_id (int32), field 2=distance (float)"""
    source_id = 0
    distance = 0.0
    has_distance = False
    pos = 0
    while pos < len(data):
        tag, pos = decode_varint(data, pos)
        field_num = tag >> 3
        wire_type = tag & 0x07
        if field_num == 1 and wire_type == 0:  # source_id varint
            source_id, pos = decode_varint(data, pos)
        elif field_num == 2 and wire_type == 5:  # distance float (fixed32)
            if pos + 4 <= len(data):
                distance = struct.unpack('<f', data[pos:pos+4])[0]
                has_distance = True
                pos += 4
        else:
            # skip unknown field
            if wire_type == 0:
                _, pos = decode_varint(data, pos)
            elif wire_type == 1:
                pos += 8
            elif wire_type == 2:
                length, pos = decode_varint(data, pos)
                pos += length
            elif wire_type == 5:
                pos += 4
            else:
                break
    return source_id, distance, has_distance

def parse_event(data):
    """Parse top-level Event, return (event_type, details)"""
    pos = 0
    event_type = None
    details = None
    while pos < len(data):
        tag, pos = decode_varint(data, pos)
        field_num = tag >> 3
        wire_type = tag & 0x07
        if wire_type == 2:  # length-delimited
            length, pos = decode_varint(data, pos)
            field_data = data[pos:pos+length]
            pos += length
            if field_num == 10:  # distance_measurement
                sid, dist, has_dist = parse_distance_measurement(field_data)
                event_type = "distance"
                details = {"source_id": sid, "distance": dist, "has_distance": has_dist, "raw_hex": field_data.hex()}
            elif field_num == 12:
                event_type = "geolocation"
            elif field_num == 13:
                event_type = "userInput"
            elif field_num == 14:
                # text_message - try to extract text
                event_type = "textMessage"
                details = {"raw": field_data}
            elif field_num == 6:
                pass  # time field, skip
            else:
                if event_type is None:
                    event_type = f"field_{field_num}"
        elif wire_type == 0:
            _, pos = decode_varint(data, pos)
        elif wire_type == 1:
            pos += 8
        elif wire_type == 5:
            pos += 4
        else:
            break
    return event_type, details

def main():
    print(f"Connecting to {PORT} @ {BAUD}...")
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    print("Connected. Reading events... (Ctrl+C to stop)\n")

    buf = bytearray()
    count = 0
    dist_zero = 0
    dist_ok = 0
    start = time.time()

    try:
        while True:
            chunk = ser.read(256)
            if not chunk:
                continue
            buf.extend(chunk)

            while b'\x00' in buf:
                idx = buf.index(b'\x00')
                frame = bytes(buf[:idx])
                buf = buf[idx+1:]

                if not frame:
                    continue

                decoded = cobs_decode(frame)
                if decoded is None:
                    print(f"  [COBS decode error, frame {len(frame)} bytes]")
                    continue

                event_type, details = parse_event(decoded)
                count += 1
                elapsed = time.time() - start

                if event_type == "distance":
                    d = details
                    if d["distance"] == 0.0 and not d["has_distance"]:
                        dist_zero += 1
                        marker = " *** ZERO (no distance field) ***"
                    elif d["distance"] == 0.0:
                        dist_zero += 1
                        marker = " *** ZERO (explicit 0.0) ***"
                    else:
                        dist_ok += 1
                        marker = ""
                    print(f"[{elapsed:7.1f}s] #{count:5d}  DIST  sid={d['source_id']}  dist={d['distance']:.3f}m  has_field={d['has_distance']}  raw={d['raw_hex']}{marker}")
                elif event_type == "geolocation":
                    print(f"[{elapsed:7.1f}s] #{count:5d}  GEO")
                elif event_type == "userInput":
                    print(f"[{elapsed:7.1f}s] #{count:5d}  BUTTON")
                elif event_type == "textMessage":
                    print(f"[{elapsed:7.1f}s] #{count:5d}  TEXT  {details}")
                else:
                    print(f"[{elapsed:7.1f}s] #{count:5d}  {event_type}  ({len(decoded)} bytes)")

    except KeyboardInterrupt:
        elapsed = time.time() - start
        print(f"\n--- Stopped after {elapsed:.1f}s ---")
        print(f"Total events: {count}")
        print(f"Distance OK: {dist_ok}, Distance ZERO: {dist_zero}")
        if dist_ok + dist_zero > 0:
            print(f"Zero rate: {dist_zero/(dist_ok+dist_zero)*100:.1f}%")
        ser.close()

if __name__ == "__main__":
    main()
