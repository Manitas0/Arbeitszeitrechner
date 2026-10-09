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

