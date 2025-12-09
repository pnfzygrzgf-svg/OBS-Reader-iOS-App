// SplashView.swift

import SwiftUI

/// Einfacher Splash-Screen, der beim App-Start kurz angezeigt wird.
///
/// Animation in 3 Phasen:
/// 1. Hashtag-Text fadet ein und „kommt auf dich zu“
/// 2. Skaliert federnd auf Endgröße zurück
/// 3. Untertitel blendet weich ein und gleitet leicht nach oben
struct SplashView: View {
    /// Gesamt-Opacity des oberen Textes (für Fade-In)
    @State private var overallOpacity: Double = 0.0
    /// Skalierung des Hashtag-Texts (Start etwas kleiner, dann größer, dann final 1.0)
    @State private var text1Scale: CGFloat = 0.7      // etwas kleiner starten
    /// Steuert, ob der Untertitel sichtbar ist
    @State private var showText2 = false
    /// Y-Offset für den Untertitel (Start leicht nach unten verschoben)
    @State private var text2Offset: CGFloat = 10      // von unten „reingleiten“

    var body: some View {
        ZStack {
            // Hintergrundfarbe aus Asset-Katalog ("LaunchBackground"),
            // damit Splash konsistent zum LaunchScreen aussieht.
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 8) {
                // Haupttext / Hashtag
                Text("#Bürger*innenforschung")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(1)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)   // bei schmalen Geräten Text leicht verkleinern
                    .scaleEffect(text1Scale)   // vom State gesteuerte Skalierung
                    .opacity(overallOpacity)   // vom State gesteuerte Sichtbarkeit

                // Untertitel
                Text("für Verkehrssicherheit")
                    .font(.headline)
                    .opacity(showText2 ? 1.0 : 0.0)           // weich ein-/ausblenden
                    .offset(y: showText2 ? 0 : text2Offset)   // animiertes „hochgleiten“
            }
        }
        // Wird beim Erscheinen des Views ausgeführt (async-Kontext für Task.sleep)
        .task {
            await runAnimation()
        }
    }

    /// Führt die Splash-Animation sequentiell aus.
    /// Muss am MainActor laufen, da UI-States geändert werden.
    @MainActor
    private func runAnimation() async {
        // Phase 1: Einblenden + leichtes „auf dich zukommen“
        withAnimation(.easeOut(duration: 0.4)) {
            overallOpacity = 1.0
            text1Scale = 1.15       // etwas größer als final
        }

        // kurze Pause, bis Phase 2 startet
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Phase 2: Zur Ruhe „einschnappen“ mit Feder-Effekt
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            text1Scale = 1.0
        }

        // kleine Pause vor dem Untertitel
        try? await Task.sleep(nanoseconds: 450_000_000)

        // Phase 3: Untertitel weich einblenden + hochgleiten
        withAnimation(.easeOut(duration: 0.4)) {
            showText2 = true
            text2Offset = 0
        }
    }
}
