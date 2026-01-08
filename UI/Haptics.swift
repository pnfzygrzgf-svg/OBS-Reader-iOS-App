// Haptics.swift

import UIKit

/// Zentraler Helfer für haptisches Feedback (Vibrationen) in der App.
///
/// Warum als Singleton?
/// - Du willst überall in der App einfach `Haptics.shared.success()` etc. aufrufen.
/// - Ein gemeinsamer Generator reicht völlig aus.
///
/// Warum @MainActor?
/// - UIKit-Feedback-Generatoren sollten auf dem Main Thread benutzt werden.
/// - So verhindert der Compiler/Runtime falsche Thread-Nutzung.
///
/// OPTIK-HINWEIS:
/// - Haptics selbst hat keine UI-Optik, bleibt aber als Teil des "UI Feel" wichtig.
@MainActor
final class Haptics {

    /// Globale, gemeinsam genutzte Instanz.
    static let shared = Haptics()

    /// iOS-Generator für „Notification“-Feedback:
    /// - .success / .warning / .error
    private let generator = UINotificationFeedbackGenerator()

    /// Private init verhindert, dass außen weitere Instanzen erstellt werden.
    private init() {}

    /// Spielt ein „Success“-Haptik aus (z.B. nach erfolgreichem Start/Stop).
    func success() {
        // prepare() reduziert die Latenz, wenn danach sofort Feedback ausgelöst wird.
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// Spielt ein „Warning“-Haptik aus (z.B. wenn Aktion nicht möglich ist).
    func warning() {
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    /// Spielt ein „Error“-Haptik aus (z.B. bei Upload-/Verbindungsfehlern).
    func error() {
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}
