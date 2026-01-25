import SwiftUI

/// Sheet zur Bewertung eines Überholvorgangs mit der 4-Stufen-Bedrohungsskala
struct ThreatRatingView: View {
    let event: LocalOvertakeEvent
    let onRate: (ThreatLevel?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: ThreatLevel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Event-Info Header
                VStack(spacing: 8) {
                    Text("\(event.distanceCm) cm")
                        .font(.system(size: 36, weight: .bold, design: .rounded))

                    Text(formatDate(event.timestamp))
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                Divider()

                // Bewertungs-Optionen
                VStack(spacing: 12) {
                    ForEach(ThreatLevel.allCases) { level in
                        Button {
                            selectedLevel = level
                        } label: {
                            threatLevelRow(level)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Bewertung entfernen Option
                if event.threatLevel != nil {
                    Button("Bewertung entfernen", role: .destructive) {
                        onRate(nil)
                        dismiss()
                    }
                    .font(.obsFootnote)
                }
            }
            .navigationTitle("Bedrohungsbewertung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        onRate(selectedLevel)
                        dismiss()
                    }
                    .disabled(selectedLevel == nil && event.threatLevel == nil)
                }
            }
        }
        .onAppear {
            selectedLevel = event.threatLevel
        }
    }

    @ViewBuilder
    private func threatLevelRow(_ level: ThreatLevel) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(level.color)
                .frame(width: 32, height: 32)
                .overlay {
                    Text("\(level.rawValue)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(level.displayName)
                    .font(.obsSectionTitle)
                    .foregroundStyle(.primary)

                Text(level.description)
                    .font(.obsFootnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selectedLevel == level {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(level.color)
                    .font(.title3)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selectedLevel == level ? level.color.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selectedLevel == level ? level.color : Color.obsCardBorderV2, lineWidth: 1)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
