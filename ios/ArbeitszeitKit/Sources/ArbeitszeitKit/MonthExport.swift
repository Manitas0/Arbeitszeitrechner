/// Stundenzettel für einen Monat als CSV (für Excel, Numbers, Google Tabellen).
public enum MonthExport {

    public struct Summary: Hashable, Sendable {
        public var workedMinutes: Int
        public var absenceMinutes: Int
        public var workDays: Int
        public var absenceDays: Int

        public init(workedMinutes: Int, absenceMinutes: Int, workDays: Int, absenceDays: Int) {
            self.workedMinutes = workedMinutes
            self.absenceMinutes = absenceMinutes
            self.workDays = workDays
            self.absenceDays = absenceDays
        }

        public var totalMinutes: Int {
            return workedMinutes + absenceMinutes
        }
    }

    /// Byte-Order-Mark, damit Excel die Datei als UTF-8 (Umlaute) erkennt.
    private static let byteOrderMark = "\u{FEFF}"
    private static let separator = ";"
    private static let lineEnd = "\r\n"

    /// MIME-Typ zum Teilen der Datei.
    public static let mimeType = "text/csv"

    /// "Arbeitszeit-2026-09.csv"
    public static func fileName(month: YearMonth) -> String {
        return "Arbeitszeit-" + pad4(month.year) + "-" + pad2(month.month) + ".csv"
    }

    /// Titel beim Teilen, z. B. "Stundenzettel September 2026".
    public static func title(month: YearMonth) -> String {
        return "Stundenzettel " + germanMonthName(month)
    }

    private static func daysWithEntries(month: YearMonth, entries: [LocalDate: DayEntry]) -> [DayEntry] {
        var result: [DayEntry] = []
        for day in 1...month.lengthOfMonth {
            if let entry = entries[month.atDay(day)], !entry.isEmpty {
                result.append(entry)
            }
        }
        return result
    }

    public static func summary(month: YearMonth, entries: [LocalDate: DayEntry], settings: AppSettings) -> Summary {
        let results = daysWithEntries(month: month, entries: entries).map { entry -> DayResult in
            WorkCalculator.evaluate(entry: entry, settings: settings)
        }
        let absences = results.filter { $0.entry.type.isAbsence }
        let work = results.filter { !$0.entry.type.isAbsence }
        return Summary(
            workedMinutes: work.reduce(0) { $0 + $1.creditedMinutes },
            absenceMinutes: absences.reduce(0) { $0 + $1.creditedMinutes },
            workDays: work.filter { $0.creditedMinutes > 0 }.count,
            absenceDays: absences.count
        )
    }

    public static func csv(month: YearMonth, entries: [LocalDate: DayEntry], settings: AppSettings) -> String {
        var lines: [[String]] = []
        lines.append([title(month: month)])
        lines.append([])
        lines.append([
            "KW", "Datum", "Wochentag", "Art", "Beginn", "Ende", "Pause (Min.)",
            "Stunden (h:mm)", "Stunden (dezimal)",
        ])
        for entry in daysWithEntries(month: month, entries: entries) {
            let result = WorkCalculator.evaluate(entry: entry, settings: settings)
            let isWork = !entry.type.isAbsence
            let start = isWork ? (entry.start.map { formatTime($0) } ?? "") : ""
            let end = isWork ? (entry.end.map { formatTime($0) } ?? "") : ""
            let breakText = isWork ? String(result.breakMinutes) : ""
            lines.append([
                String(entry.date.isoWeek),
                formatLongDate(entry.date),
                germanDayName(entry.date),
                entry.type.label,
                start,
                end,
                breakText,
                formatDuration(result.creditedMinutes),
                formatDecimalHours(result.creditedMinutes),
            ])
        }
        let totals = summary(month: month, entries: entries, settings: settings)
        lines.append([])
        lines.append(sumLine("Summe gearbeitet", totals.workedMinutes))
        if totals.absenceMinutes > 0 {
            lines.append(sumLine("Gutschrift Urlaub/Krank/Feiertag", totals.absenceMinutes))
            lines.append(sumLine("Gesamt", totals.totalMinutes))
        }
        let body = lines.map { $0.joined(separator: MonthExport.separator) }.joined(separator: MonthExport.lineEnd)
        return MonthExport.byteOrderMark + body + MonthExport.lineEnd
    }

    private static func sumLine(_ label: String, _ minutes: Int) -> [String] {
        return [label, "", "", "", "", "", "", formatDuration(minutes), formatDecimalHours(minutes)]
    }
}
