import Foundation
import WidgetKit
import ArbeitszeitKit

/// Lokale Speicherung von Einträgen und Einstellungen – gemeinsam für App, Widgets, Kontrollzentrum und Siri.
///
/// Die Daten liegen in den UserDefaults der App Group (Info.plist-Schlüssel `AZAppGroup`), damit Widgets
/// dieselben Daten sehen wie die App. Ohne App Group (z. B. unsigniert im Simulator oder nach Sideloadly)
/// werden die Standard-UserDefaults der App benutzt. Mit den Startargumenten für Bildschirmfotos
/// (`-AZDemoData`, `-AZFixedNow`) nutzt die App einen eigenen Speicher, damit Beispieldaten und
/// Stempel mit fester Uhrzeit nie in den echten Daten landen.
///
/// Format wie in der Android-App: Einträge als JSON `{"YYYY-MM-DD": {"type": "WORK", "start": "08:00", …}}`,
/// Einstellungen im selben JSON wie in der Sicherungsdatei.
final class WorkStorage {
    private enum Key {
        static let entries = "entries"
        static let settings = "settings"
        /// Zustand der automatischen Sicherung (siehe AutoBackup in der App)
        static let backupBookmark = "autoBackupBookmark"
        static let backupLastSuccess = "autoBackupLastSuccess"
        static let backupError = "autoBackupError"
        static let backupPending = "autoBackupPending"
        static let backupState = [backupBookmark, backupLastSuccess, backupError]
        /// Endung für Daten, die bereits in die App Group übernommen wurden
        static let migratedSuffix = ".migrated"
        /// Nicht lesbarer Text der Einträge wird hier aufbewahrt statt überschrieben
        static let unreadablePrefix = "entries.unreadable."
    }

    private static let demoSuiteName = "de.arbeitszeitrechner.demo"

    let defaults: UserDefaults
    /// true: Die Daten liegen in der App Group und sind für Widgets und Kontrollzentrum sichtbar.
    let isShared: Bool
    /// true: eigener Speicher für Bildschirmfotos (siehe LaunchOptions).
    let isDemo: Bool

    init() {
        if LaunchOptions.usesDemoStorage, let demo = UserDefaults(suiteName: WorkStorage.demoSuiteName) {
            defaults = demo
            // Wie im Normalbetrieb, damit Bildschirmfotos dieselben Hinweise zeigen.
            isShared = WorkStorage.appGroupDefaults() != nil
            isDemo = true
        } else if let shared = WorkStorage.appGroupDefaults() {
            // Nur in der App: Die Widget-Erweiterung hat eigene, leere Standard-UserDefaults.
            if !WorkStorage.isAppExtension {
                WorkStorage.migrateStandardDefaults(to: shared)
            }
            defaults = shared
            isShared = true
            isDemo = false
        } else {
            defaults = UserDefaults.standard
            isShared = false
            isDemo = false
        }
    }

    /// true im Prozess der Widget-Erweiterung.
    static var isAppExtension: Bool {
        return Bundle.main.bundlePath.hasSuffix(".appex")
    }

    /// App Group aus der Info.plist, nil wenn keine eingetragen ist.
    static var appGroupID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AZAppGroup") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leer oder nicht ersetzte Build-Variable: keine App Group.
        if trimmed.isEmpty || trimmed.contains("$(") {
            return nil
        }
        return trimmed
    }

    /// Nur wenn die App Group wirklich freigeschaltet ist (Entitlement vorhanden). Sonst würden
    /// die Daten auf dem Gerät womöglich nicht dauerhaft gespeichert.
    private static func appGroupDefaults() -> UserDefaults? {
        guard let group = appGroupID,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
        else { return nil }
        return UserDefaults(suiteName: group)
    }

    /// Übernimmt Daten, die ohne App Group gespeichert wurden (z. B. nach einer Installation mit Sideloadly),
    /// in die App Group – auch wenn dort schon etwas steht, etwa ein Stempel aus dem Widget. Bei gleichem
    /// Tag gewinnt der Eintrag in der App Group. Danach werden die alten Schlüssel umbenannt, damit eine
    /// spätere Installation ohne App Group keinen veralteten Stand als aktuell anzeigt.
    private static func migrateStandardDefaults(to shared: UserDefaults) {
        let standard = UserDefaults.standard
        let oldKeys = [Key.entries, Key.settings, Key.backupPending] + Key.backupState
        guard oldKeys.contains(where: { standard.object(forKey: $0) != nil }) else { return }

        if let oldText = standard.string(forKey: Key.entries) {
            let oldEntries = BackupFormat.decodeEntries(oldText)
            if !oldEntries.isEmpty {
                let current = shared.string(forKey: Key.entries).map { BackupFormat.decodeEntries($0) } ?? [:]
                let merged = BackupFormat.merge(existing: oldEntries, restored: Array(current.values))
                writeEntries(merged, to: shared)
                shared.set(true, forKey: Key.backupPending)
            }
            standard.set(oldText, forKey: Key.entries + Key.migratedSuffix)
            standard.removeObject(forKey: Key.entries)
        }
        if let oldSettings = standard.string(forKey: Key.settings) {
            if shared.string(forKey: Key.settings) == nil {
                shared.set(oldSettings, forKey: Key.settings)
            }
            standard.set(oldSettings, forKey: Key.settings + Key.migratedSuffix)
            standard.removeObject(forKey: Key.settings)
        }
        // Automatische Sicherung nur übernehmen, wenn in der App Group keine eingerichtet ist.
        if standard.data(forKey: Key.backupBookmark) != nil && shared.data(forKey: Key.backupBookmark) == nil {
            for key in Key.backupState {
                shared.set(standard.object(forKey: key), forKey: key)
            }
            shared.set(true, forKey: Key.backupPending)
        }
        for key in [Key.backupPending] + Key.backupState {
            standard.removeObject(forKey: key)
        }
    }

    // MARK: Einträge

    func loadEntries() -> [LocalDate: DayEntry] {
        guard let text = defaults.string(forKey: Key.entries) else { return [:] }
        return BackupFormat.decodeEntries(text)
    }

    func loadEntry(_ date: LocalDate) -> DayEntry {
        return loadEntries()[date] ?? DayEntry(date: date)
    }

    /// Speichert einen Eintrag; leere Einträge werden entfernt.
    func saveEntry(_ entry: DayEntry) {
        var entries = loadEntries()
        entries[entry.date] = entry.isEmpty ? nil : entry
        WorkStorage.writeEntries(entries, to: defaults)
        didChange()
    }

    func deleteEntry(_ date: LocalDate) {
        var entries = loadEntries()
        entries[date] = nil
        WorkStorage.writeEntries(entries, to: defaults)
        didChange()
    }

    /// Ersetzt alle Einträge (z. B. nach dem Wiederherstellen einer Sicherung).
    func replaceEntries(_ entries: [LocalDate: DayEntry]) {
        WorkStorage.writeEntries(entries, to: defaults)
        didChange()
    }

    /// Alle Einträge stehen als ein JSON-Text unter einem Schlüssel. Lässt sich der bisherige Text nicht
    /// lesen (beschädigt), wird er vorher aufbewahrt, statt ihn mit den übrigen Tagen zu überschreiben.
    private static func writeEntries(_ entries: [LocalDate: DayEntry], to defaults: UserDefaults) {
        if let old = defaults.string(forKey: Key.entries), isUnreadable(old) {
            defaults.set(old, forKey: Key.unreadablePrefix + LocalDateTime.now().iso)
        }
        defaults.set(BackupFormat.encodeEntries(entries.values), forKey: Key.entries)
    }

    /// Text vorhanden, aber kein einziger Eintrag lesbar.
    private static func isUnreadable(_ text: String) -> Bool {
        guard BackupFormat.decodeEntries(text).isEmpty else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "{}"
    }

    // MARK: Einstellungen

    func loadSettings() -> AppSettings {
        guard let text = defaults.string(forKey: Key.settings),
              let settings = BackupFormat.decodeSettings(text)
        else { return AppSettings() }
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        defaults.set(BackupFormat.encodeSettings(settings), forKey: Key.settings)
        didChange()
    }

    // MARK: Stempeln

    /// Kommen bzw. Gehen für heute (wie TimeClock.toggle in Android).
    /// Liefert die ausgeführte Aktion und den neuen Eintrag, oder nil, wenn nichts zu tun war.
    @discardableResult
    func stampClock(at now: LocalDateTime) -> (action: ClockAction, entry: DayEntry)? {
        let entry = loadEntry(now.date)
        guard let result = toggleClock(entry, at: now.time) else { return nil }
        saveEntry(result.entry)
        return result
    }

    // MARK: Automatische Sicherung
    //
    // Der Zustand liegt bei den Daten und zieht so bei einem Wechsel mit/ohne App Group mit um.
    // Eine Installation, die die Daten nicht sieht, darf die Sicherungsdatei nicht überschreiben.

    /// Lesezeichen (Security-Scoped Bookmark) der Sicherungsdatei; nil, wenn die automatische Sicherung aus ist.
    var backupBookmark: Data? {
        get { return defaults.data(forKey: Key.backupBookmark) }
        set { defaults.set(newValue, forKey: Key.backupBookmark) }
    }

    var backupLastSuccess: LocalDateTime? {
        get { return defaults.string(forKey: Key.backupLastSuccess).flatMap { LocalDateTime(iso: $0) } }
        set { defaults.set(newValue?.iso, forKey: Key.backupLastSuccess) }
    }

    var backupError: String? {
        get { return defaults.string(forKey: Key.backupError) }
        set { defaults.set(newValue, forKey: Key.backupError) }
    }

    /// Merkt sich eine Änderung (auch aus Widgets und Kontrollzentrum); die App sichert dann neu.
    func markBackupPending() {
        defaults.set(true, forKey: Key.backupPending)
    }

    /// true, wenn sich seit der letzten Sicherung etwas geändert hat; setzt die Markierung zurück.
    func takeBackupPending() -> Bool {
        guard defaults.bool(forKey: Key.backupPending) else { return false }
        defaults.set(false, forKey: Key.backupPending)
        return true
    }

    // MARK: Benachrichtigung

    private func didChange() {
        markBackupPending()
        WorkStorage.notifyChange()
    }

    /// Widgets und Steuerelemente im Kontrollzentrum neu zeichnen lassen.
    static func notifyChange() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }
}
