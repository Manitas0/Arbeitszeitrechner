import Foundation
import ArbeitszeitKit

/// Kommen/Gehen stempeln mit kurzer Rückmeldung – für Siri, Kurzbefehle, Widget und Kontrollzentrum.
enum ClockService {

    /// Führt die nächste Stempel-Aktion für heute aus und liefert die Meldung dazu.
    static func toggle(storage: WorkStorage = WorkStorage(), now: LocalDateTime = AppTime.now()) -> String {
        // Ohne App Group sieht die Widget-Erweiterung andere Daten als die App: lieber nichts ändern.
        if WorkStorage.isAppExtension && !storage.isShared {
            return "Ohne App-Gruppe kann nur in der App gestempelt werden."
        }
        if let result = storage.stampClock(at: now) {
            return message(for: result.action, entry: result.entry)
        }
        let entry = storage.loadEntry(now.date)
        if entry.type.isAbsence {
            return "Heute: \(entry.type.label) \u{2013} nichts zu stempeln."
        }
        return "Heute ist schon fertig gestempelt."
    }

    /// "Eingestempelt um 08:00" bzw. "Ausgestempelt um 16:30" (wie die Android-Widgets).
    static func message(for action: ClockAction, entry: DayEntry) -> String {
        switch action {
        case .clockIn:
            return "Eingestempelt um " + (entry.start.map { formatTime($0) } ?? "")
        case .clockOut:
            return "Ausgestempelt um " + (entry.end.map { formatTime($0) } ?? "")
        }
    }
}

extension ClockAction {
    /// SF-Symbol für Knöpfe und das Kontrollzentrum.
    var symbolName: String {
        switch self {
        case .clockIn:
            return "figure.walk.arrival"
        case .clockOut:
            return "figure.walk.departure"
        }
    }
}
