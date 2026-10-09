import Foundation
import ArbeitszeitKit

/// Startargumente für automatisierte Bildschirmfotos (UI-Test). Ohne diese Argumente wirkungslos.
///
/// - `-AZDemoData YES`: zeigt Beispieldaten
/// - `-AZFixedNow 2026-09-30T15:00`: feste Uhrzeit für "jetzt"
/// - `-AZWidgetPreview YES`: zeigt statt der App eine Seite mit den Widget-Ansichten
///
/// Mit `-AZDemoData` oder `-AZFixedNow` arbeitet die App in einem eigenen Speicher, der bei jedem Start
/// zurückgesetzt wird (siehe WorkStorage). Die echten Daten bleiben unberührt.
/// Gelesen wird nur aus den Startargumenten, nie aus gespeicherten Einstellungen.
enum LaunchOptions {
    static let demoData: Bool = flag("AZDemoData")
    static let widgetPreview: Bool = flag("AZWidgetPreview")
    static let fixedNow: LocalDateTime? = value("AZFixedNow").flatMap { LocalDateTime(iso: $0) }

    static var usesDemoStorage: Bool {
        return demoData || fixedNow != nil
    }

    private static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func flag(_ name: String) -> Bool {
        guard let text = value(name)?.lowercased() else { return false }
        return text == "yes" || text == "true" || text == "1"
    }
}

/// Zeitquelle für "jetzt": die Uhr des Geräts oder die feste Zeit aus `-AZFixedNow`.
/// (Bewusst nicht "Clock" genannt – das ist ein Protokoll der Swift-Standardbibliothek.)
enum AppTime {
    static func now() -> LocalDateTime {
        return LaunchOptions.fixedNow ?? LocalDateTime.now()
    }
}
