#!/usr/bin/env python3
"""Read OBS Lite sensor data via BLE (same as the iOS app receives)."""

import asyncio
import struct
import time
import sys

from bleak import BleakClient, BleakScanner

DEVICE_NAME = "OBS Lite LiDAR"
TX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

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
    source_id = 0
    distance = 0.0
    has_distance = False
    pos = 0
    while pos < len(data):
        tag, pos = decode_varint(data, pos)
        field_num = tag >> 3
        wire_type = tag & 0x07
        if field_num == 1 and wire_type == 0:
            source_id, pos = decode_varint(data, pos)
        elif field_num == 2 and wire_type == 5:
            if pos + 4 <= len(data):
                distance = struct.unpack('<f', data[pos:pos+4])[0]
                has_distance = True
                pos += 4
        else:
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
    pos = 0
    event_type = None
    details = None
    while pos < len(data):
        if pos >= len(data):
            break
        tag, pos = decode_varint(data, pos)
        field_num = tag >> 3
        wire_type = tag & 0x07
        if wire_type == 2:
            length, pos = decode_varint(data, pos)
            if pos + length > len(data):
                # Truncated!
                return "TRUNCATED", {"field": field_num, "expected": length, "available": len(data) - pos, "raw_hex": data.hex()}
            field_data = data[pos:pos+length]
            pos += length
            if field_num == 10:
                sid, dist, has_dist = parse_distance_measurement(field_data)
                event_type = "distance"
                details = {"source_id": sid, "distance": dist, "has_distance": has_dist, "raw_hex": field_data.hex(), "dm_bytes": len(field_data)}
            elif field_num == 12:
                event_type = "geolocation"
            elif field_num == 13:
                event_type = "userInput"
            elif field_num == 14:
                event_type = "textMessage"
                details = {"raw": field_data}
            elif field_num == 6:
                pass  # time
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

# Stats
start_time = None
count = 0
dist_zero_no_field = 0
dist_zero_explicit = 0
dist_ok = 0
truncated = 0
sid1_zero = 0
sid1_ok = 0
sid2_zero = 0
sid2_ok = 0

def handle_notification(sender, data: bytearray):
    """Each BLE notification = one protobuf event (no COBS on BLE)."""
    global start_time, count, dist_zero_no_field, dist_zero_explicit, dist_ok, truncated
    global sid1_zero, sid1_ok, sid2_zero, sid2_ok

    if start_time is None:
        start_time = time.time()

    count += 1
    elapsed = time.time() - start_time

    event_type, details = parse_event(bytes(data))

    if event_type == "TRUNCATED":
        truncated += 1
        print(f"[{elapsed:7.1f}s] #{count:5d}  *** TRUNCATED ***  field={details['field']} expected={details['expected']} got={details['available']}  raw={details['raw_hex']}")
    elif event_type == "distance":
        d = details
        sid = d["source_id"]
        if d["distance"] == 0.0 and not d["has_distance"]:
            dist_zero_no_field += 1
            if sid == 1: sid1_zero += 1
            else: sid2_zero += 1
            print(f"[{elapsed:7.1f}s] #{count:5d}  DIST  sid={sid}  dist=0.000m  *** NO DISTANCE FIELD ***  dm_bytes={d['dm_bytes']}  raw={d['raw_hex']}  full={data.hex()}")
        elif d["distance"] == 0.0:
            dist_zero_explicit += 1
            if sid == 1: sid1_zero += 1
            else: sid2_zero += 1
            print(f"[{elapsed:7.1f}s] #{count:5d}  DIST  sid={sid}  dist=0.000m  *** EXPLICIT ZERO ***  raw={d['raw_hex']}  full={data.hex()}")
        else:
            dist_ok += 1
            if sid == 1: sid1_ok += 1
            else: sid2_ok += 1
            # Only print every 50th OK event to reduce noise
            if dist_ok % 50 == 1:
                print(f"[{elapsed:7.1f}s] #{count:5d}  DIST  sid={sid}  dist={d['distance']:.3f}m  OK  (showing every 50th)")
    elif event_type == "geolocation":
        pass  # silent
    elif event_type == "userInput":
        print(f"[{elapsed:7.1f}s] #{count:5d}  BUTTON")
    elif event_type == "textMessage":
        print(f"[{elapsed:7.1f}s] #{count:5d}  TEXT  {details}")
    else:
        print(f"[{elapsed:7.1f}s] #{count:5d}  {event_type}  ({len(data)} bytes)  raw={data.hex()}")

async def main():
    global start_time
    print(f"Scanning for '{DEVICE_NAME}'...")

    device = await BleakScanner.find_device_by_name(DEVICE_NAME, timeout=10)
    if not device:
        print(f"Device '{DEVICE_NAME}' not found. Available devices:")
        devices = await BleakScanner.discover(timeout=5)
        for d in devices:
            print(f"  {d.name} ({d.address})")
        sys.exit(1)

    print(f"Found: {device.name} ({device.address})")
    print(f"Connecting...")

    async with BleakClient(device) as client:
        mtu = client.mtu_size
        print(f"Connected! MTU={mtu}")
        print(f"Subscribing to TX characteristic...")
        print(f"Reading events... (Ctrl+C to stop)\n")

        await client.start_notify(TX_CHAR_UUID, handle_notification)

        try:
            # Run for 120 seconds max
            for i in range(240):
                await asyncio.sleep(0.5)
                # Print stats every 10 seconds
                if start_time and (i+1) % 20 == 0:
                    elapsed = time.time() - start_time
                    total_dist = dist_ok + dist_zero_no_field + dist_zero_explicit
                    zero_total = dist_zero_no_field + dist_zero_explicit
                    print(f"\n--- Stats at {elapsed:.0f}s: events={count}, dist_ok={dist_ok}, zero_no_field={dist_zero_no_field}, zero_explicit={dist_zero_explicit}, truncated={truncated} ---")
                    print(f"    sid1: ok={sid1_ok} zero={sid1_zero} | sid2: ok={sid2_ok} zero={sid2_zero}")
                    if total_dist > 0:
                        print(f"    Zero rate: {zero_total/total_dist*100:.1f}%")
                    print()
        except KeyboardInterrupt:
            pass

        await client.stop_notify(TX_CHAR_UUID)

    elapsed = time.time() - start_time if start_time else 0
    total_dist = dist_ok + dist_zero_no_field + dist_zero_explicit
    zero_total = dist_zero_no_field + dist_zero_explicit
    print(f"\n=== FINAL RESULTS ({elapsed:.0f}s) ===")
    print(f"Total events: {count}")
    print(f"Distance OK: {dist_ok}")
    print(f"Distance ZERO (no field): {dist_zero_no_field}")
    print(f"Distance ZERO (explicit): {dist_zero_explicit}")
    print(f"Truncated: {truncated}")
    print(f"sid1: ok={sid1_ok} zero={sid1_zero}")
    print(f"sid2: ok={sid2_ok} zero={sid2_zero}")
    if total_dist > 0:
        print(f"Zero rate: {zero_total/total_dist*100:.1f}%")

if __name__ == "__main__":
    asyncio.run(main())
