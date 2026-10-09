import AppIntents
import ArbeitszeitKit

/// "Stempeln": Kommen bzw. Gehen für heute auf die aktuelle Uhrzeit.
/// Genutzt vom Widget-Knopf, vom Kontrollzentrum (iOS 18), von Siri/Kurzbefehlen und in der App.
struct ToggleClockIntent: AppIntent {
    static var title: LocalizedStringResource { "Stempeln" }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = ClockService.toggle()
        return .result(dialog: "\(message)")
    }
}

/// Öffnet die App. Für das Kontrollzentrum, wenn heute nichts zu stempeln ist (wie die Android-Kachel).
/// Liegt in App und Widgets, sonst kann ein Steuerelement die App nicht öffnen.
struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource { "Arbeitszeit öffnen" }
    static var openAppWhenRun: Bool { true }
    /// Keine eigene Aktion in der Kurzbefehle-App.
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
