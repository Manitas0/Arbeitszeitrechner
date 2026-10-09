import Foundation

/// Inhalt einer Sicherungsdatei.
public struct BackupData: Hashable, Sendable {
    public var createdAt: LocalDateTime?
    public var settings: AppSettings?
    public var entries: [DayEntry]

    public init(createdAt: LocalDateTime?, settings: AppSettings?, entries: [DayEntry]) {
        self.createdAt = createdAt
        self.settings = settings
        self.entries = entries
    }

    /// Übernimmt die Sicherung wie Android: Einträge aus der Sicherung ersetzen die Einträge
    /// derselben Tage, alle anderen Tage bleiben erhalten; die Einstellungen werden übernommen.
    public func restore(
        into entries: [LocalDate: DayEntry],
        settings: AppSettings
    ) -> (entries: [LocalDate: DayEntry], settings: AppSettings) {
        let merged = BackupFormat.merge(existing: entries, restored: self.entries)
        return (entries: merged, settings: self.settings ?? settings)
    }
}

/// Fehler beim Lesen einer Sicherung oder eines Eintrags.
public enum BackupError: Error, Hashable, Sendable, CustomStringConvertible {
    /// Die Datei ist keine Sicherung des Arbeitszeitrechners.
    case notABackup
    /// Ein Eintrag enthält eine ungültige Uhrzeit.
    case invalidEntry(String)

    public var message: String {
        switch self {
        case .notABackup:
            return "Das ist keine Sicherungsdatei des Arbeitszeitrechners."
        case .invalidEntry(let detail):
            return detail
        }
    }

    public var description: String {
        return message
    }
}

extension BackupError: LocalizedError {
    public var errorDescription: String? {
        return message
    }
}

/// JSON-Format für gespeicherte Einträge und Sicherungsdateien, kompatibel mit der Android-App.
///
/// Sicherungsdatei:
/// `{"app": "Arbeitszeitrechner", "version": 1, "createdAt": "2026-09-30T14:55:12",
///   "settings": {"weeklyTargetMinutes": 1200, "workDaysPerWeek": 2, "weeklyHoursAreLimit": true,
///                "autoBreak": true, "gradualDeduction": true, "breakRules": [{"after": 360, "break": 30}, …]},
///   "entries": [{"date": "2026-09-28", "type": "WORK", "start": "08:00", "end": "16:30", "break": 0}, …]}`
public enum BackupFormat {

    public static let appID = "Arbeitszeitrechner"
    public static let version = 1
    /// Vorgeschlagener Dateiname für eine Sicherung.
    public static let suggestedFileName = "Arbeitszeitrechner-Backup.json"
    public static let mimeType = "application/json"

    // MARK: Einträge

    /// Eintrag ohne Datum als `[String: Any]`: type, start/end (nur wenn gesetzt), break.
    public static func encodeEntry(_ entry: DayEntry) -> [String: Any] {
        var json: [String: Any] = [
            "type": entry.type.rawValue,
            "break": entry.manualBreakMinutes,
        ]
        if let start = entry.start {
            json["start"] = start.iso
        }
        if let end = entry.end {
            json["end"] = end.iso
        }
        return json
    }

    /// Liest einen Eintrag wie Android: unbekannte Art -> Arbeit, fehlende Pause -> 0, negative Pause -> 0.
    /// Wirft `BackupError.invalidEntry` bei einer ungültigen Uhrzeit (wie LocalTime.parse).
    public static func decodeEntry(date: LocalDate, json: [String: Any]) throws -> DayEntry {
        return try decodeEntryValue(date: date, json: JSONValue(any: json))
    }

    /// Ein Eintrag als kompakter JSON-Text, z. B. `{"type":"WORK","start":"08:00","break":0}`
    /// (so speichert Android jeden Tag in den SharedPreferences).
    public static func encodeEntryText(_ entry: DayEntry) -> String {
        return entryValue(entry, includeDate: false).serialized()
    }

    /// Gegenstück zu `encodeEntryText`; nil, wenn der Text ungültig ist.
    public static func decodeEntryText(date: LocalDate, text: String) -> DayEntry? {
        guard let json = JSONParser.parse(text), json.isObject else { return nil }
        return try? decodeEntryValue(date: date, json: json)
    }

    static func entryValue(_ entry: DayEntry, includeDate: Bool) -> JSONValue {
        var members: [JSONMember] = []
        if includeDate {
            members.append(JSONMember("date", .string(entry.date.iso)))
        }
        members.append(JSONMember("type", .string(entry.type.rawValue)))
        if let start = entry.start {
            members.append(JSONMember("start", .string(start.iso)))
        }
        if let end = entry.end {
            members.append(JSONMember("end", .string(end.iso)))
        }
        members.append(JSONMember("break", .number(String(entry.manualBreakMinutes))))
        return .object(members)
    }

    static func decodeEntryValue(date: LocalDate, json: JSONValue) throws -> DayEntry {
        let type = DayType(rawValue: json.optString("type")) ?? .work
        let start = try parseTime(json.optString("start"))
        let end = try parseTime(json.optString("end"))
        let manualBreak = max(json.optInt("break", 0), 0)
        return DayEntry(date: date, type: type, start: start, end: end, manualBreakMinutes: manualBreak)
    }

    private static func parseTime(_ text: String) throws -> LocalTime? {
        if text.isEmpty {
            return nil
        }
        guard let time = LocalTime(iso: text) else {
            throw BackupError.invalidEntry("Ungültige Uhrzeit: \(text)")
        }
        return time
    }

    // MARK: Einstellungen

    static func settingsValue(_ settings: AppSettings) -> JSONValue {
        let rules = settings.breakRules.map { rule -> JSONValue in
            JSONValue.object([
                JSONMember("after", .number(String(rule.afterMinutes))),
                JSONMember("break", .number(String(rule.breakMinutes))),
            ])
        }
        return .object([
            JSONMember("weeklyTargetMinutes", .number(String(settings.weeklyTargetMinutes))),
            JSONMember("workDaysPerWeek", .number(String(settings.workDaysPerWeek))),
            JSONMember("weeklyHoursAreLimit", .bool(settings.weeklyHoursAreLimit)),
            JSONMember("autoBreak", .bool(settings.autoBreak)),
            JSONMember("gradualDeduction", .bool(settings.gradualDeduction)),
            JSONMember("breakRules", .array(rules)),
        ])
    }

    /// Liest Einstellungen wie Android: fehlende Werte -> Standard, Wochenstunden auf 1 min bis 168 h
    /// und Arbeitstage auf 1 bis 7 begrenzt, immer genau zwei Pausenregeln.
    static func decodeSettingsValue(_ json: JSONValue) -> AppSettings {
        let defaults = AppSettings()
        let rulesJSON = json.optArray("breakRules")
        var rules: [BreakRule] = []
        for (index, fallback) in AppSettings.defaultBreakRules.enumerated() {
            var ruleJSON: JSONValue? = nil
            if let rulesJSON = rulesJSON, index < rulesJSON.count, rulesJSON[index].isObject {
                ruleJSON = rulesJSON[index]
            }
            let after = ruleJSON?.optInt("after", fallback.afterMinutes) ?? fallback.afterMinutes
            let breakMinutes = ruleJSON?.optInt("break", fallback.breakMinutes) ?? fallback.breakMinutes
            rules.append(BreakRule(afterMinutes: after, breakMinutes: breakMinutes))
        }
        let weekly = json.optInt("weeklyTargetMinutes", defaults.weeklyTargetMinutes)
        let days = json.optInt("workDaysPerWeek", defaults.workDaysPerWeek)
        return AppSettings(
            weeklyTargetMinutes: min(max(weekly, 1), 7 * 24 * 60),
            workDaysPerWeek: min(max(days, 1), 7),
            weeklyHoursAreLimit: json.optBoolean("weeklyHoursAreLimit", defaults.weeklyHoursAreLimit),
            autoBreak: json.optBoolean("autoBreak", defaults.autoBreak),
            gradualDeduction: json.optBoolean("gradualDeduction", defaults.gradualDeduction),
            breakRules: rules
        )
    }

    // MARK: Speicherung in der App

    /// Alle Einträge als kompaktes JSON-Objekt `{"YYYY-MM-DD": Eintrag, …}` mit demselben
    /// Eintrags-JSON wie Android. Leere Einträge werden weggelassen.
    public static func encodeEntries<S: Sequence>(_ entries: S) -> String where S.Element == DayEntry {
        let sorted = entries.filter { !$0.isEmpty }.sorted { $0.date < $1.date }
        let members = sorted.map { entry -> JSONMember in
            JSONMember(entry.date.iso, entryValue(entry, includeDate: false))
        }
        return JSONValue.object(members).serialized()
    }

    /// Gegenstück zu `encodeEntries`. Ungültige oder leere Einträge werden übersprungen.
    public static func decodeEntries(_ text: String) -> [LocalDate: DayEntry] {
        guard let json = JSONParser.parse(text), let members = json.objectMembers else { return [:] }
        var result: [LocalDate: DayEntry] = [:]
        for member in members {
            guard let date = LocalDate(iso: member.key), member.value.isObject else { continue }
            guard let entry = try? decodeEntryValue(date: date, json: member.value), !entry.isEmpty else { continue }
            result[date] = entry
        }
        return result
    }

    /// Einstellungen als kompaktes JSON (dasselbe Format wie in der Sicherungsdatei).
    public static func encodeSettings(_ settings: AppSettings) -> String {
        return settingsValue(settings).serialized()
    }

    /// Gegenstück zu `encodeSettings`; nil, wenn der Text kein JSON-Objekt ist.
    public static func decodeSettings(_ text: String) -> AppSettings? {
        guard let json = JSONParser.parse(text), json.isObject else { return nil }
        return decodeSettingsValue(json)
    }

    /// Wiederherstellen: Einträge aus der Sicherung ersetzen die Einträge derselben Tage,
    /// leere Einträge löschen den Tag, alle anderen Tage bleiben erhalten.
    public static func merge(existing: [LocalDate: DayEntry], restored: [DayEntry]) -> [LocalDate: DayEntry] {
        var result = existing
        for entry in restored {
            if entry.isEmpty {
                result[entry.date] = nil
            } else {
                result[entry.date] = entry
            }
        }
        return result
    }

    // MARK: Sicherungsdatei

    /// Sicherungsdatei als eingerücktes JSON. Leere Einträge werden weggelassen, der Rest nach Datum sortiert.
    public static func create<S: Sequence>(
        entries: S,
        settings: AppSettings,
        createdAt: LocalDateTime
    ) -> String where S.Element == DayEntry {
        let sorted = entries.filter { !$0.isEmpty }.sorted { $0.date < $1.date }
        let entryValues = sorted.map { entry -> JSONValue in
            entryValue(entry, includeDate: true)
        }
        let root = JSONValue.object([
            JSONMember("app", .string(appID)),
            JSONMember("version", .number(String(version))),
            JSONMember("createdAt", .string(createdAt.iso)),
            JSONMember("settings", settingsValue(settings)),
            JSONMember("entries", .array(entryValues)),
        ])
        return root.serialized(indent: 2)
    }

    /// Liest eine Sicherungsdatei (auch von Android). Wirft `BackupError.notABackup`,
    /// wenn es keine gültige Sicherung ist. Ungültige Einträge werden übersprungen.
    public static func parse(_ text: String) throws -> BackupData {
        var scalars = Array(text.unicodeScalars)
        if let first = scalars.first, first.value == 0xFEFF {
            scalars.removeFirst()
        }
        let body = makeString(trimmedScalars(scalars))
        // Text nach dem Objekt wird ignoriert wie bei org.json unter Android (z. B. Reste einer
        // längeren alten Datei, wenn der Speicheranbieter beim Überschreiben nicht kürzt).
        guard let json = JSONParser.parse(body, allowTrailingContent: true),
              json.isObject,
              json.optString("app") == appID
        else {
            throw BackupError.notABackup
        }
        var entries: [DayEntry] = []
        for item in json.optArray("entries") ?? [] {
            guard item.isObject, let date = LocalDate(iso: item.optString("date")) else { continue }
            if let entry = try? decodeEntryValue(date: date, json: item) {
                entries.append(entry)
            }
        }
        let createdAt = LocalDateTime(iso: json.optString("createdAt"))
        var settings: AppSettings? = nil
        if let settingsJSON = json.optObject("settings") {
            settings = decodeSettingsValue(settingsJSON)
        }
        return BackupData(createdAt: createdAt, settings: settings, entries: entries)
    }
}
