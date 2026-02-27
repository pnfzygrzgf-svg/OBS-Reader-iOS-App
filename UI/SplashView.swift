// SPDX-License-Identifier: GPL-3.0-or-later

// SplashView.swift

import SwiftUI

/// Splash mit „Text-Mask Reveal“
/// - Titel wird per animierter Maske (von links nach rechts) „aufgedeckt“
/// - Subtitle erscheint leicht verzögert (Fade + Rise)
///
/// OPTIK-UPDATE:
/// - Subtile Typo (rounded) + bessere Abstände
/// - sanfteres Timing
/// - respektiert Reduce Motion
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAnimated = false

    // Reveal-Progress (0…1) steuert die Maskenbreite
    @State private var reveal: CGFloat = 0.0

    // Subtitle Animation
    @State private var showSubtitle = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 12) {

                // MARK: - Title mit Mask Reveal
                Text("#Bürger*innenforschung")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    // Maske deckt den Text von links nach rechts auf
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: geo.size.width * reveal)
                        }
                    }
                    // optional: kleine “Premium” Bewegung
                    .opacity(reduceMotion ? 1 : (reveal > 0 ? 1 : 0))
                    .scaleEffect(reduceMotion ? 1 : (reveal > 0 ? 1.0 : 0.99))
                    .accessibilityLabel("Bürgerinnenforschung")

                // MARK: - Subtitle (staggered)
                Text("für Verkehrssicherheit")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 8)
            }
            .padding(.horizontal, 24)
        }
        .task {
            guard !hasAnimated else { return }
            hasAnimated = true
            await runAnimation()
        }
    }

    @MainActor
    private func runAnimation() async {
        // Reduce Motion: direkt anzeigen (ohne Bewegung)
        if reduceMotion {
            reveal = 1.0
            showSubtitle = true
            return
        }

        // 1) Title Reveal
        withAnimation(.easeOut(duration: 0.70)) {
            reveal = 1.0
        }

        // kleiner Stagger
        do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }

        // 2) Subtitle nachziehen (Fade + Rise)
        withAnimation(.easeOut(duration: 0.45)) {
            showSubtitle = true
        }
    }
}
