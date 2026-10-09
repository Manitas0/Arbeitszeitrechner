import ArbeitszeitKit

/// Beispieldaten für Bildschirmfotos (`-AZDemoData YES`) und die Widget-Galerie:
/// die aktuelle Woche und die vier Wochen davor (Werkstudent, 20 h an 2 Tagen).
enum DemoData {

    /// Einträge bis einschließlich `today`; heute ist seit 08:00 eingestempelt.
    static func entries(today: LocalDate) -> [LocalDate: DayEntry] {
        let week = WorkCalculator.weekStartOf(today)
        var list: [DayEntry] = [
            work(week.plusDays(-25), "08:00", "18:00", breakMinutes: 60),
            work(week.plusDays(-24), "08:00", "17:00"),
            DayEntry(date: week.plusDays(-20), type: .vacation),
            work(week.plusDays(-17), "09:00", "19:45"),
            DayEntry(date: week.plusDays(-14), type: .sick),
            work(week.plusDays(-12), "08:00", "18:45"),
            work(week.plusDays(-6), "08:00", "18:00"),
            work(week.plusDays(-4), "07:30", "18:30"),
        ]
        if today != week {
            // Montag 10:30 h: 08:00–19:15 mit 45 min automatischer Pause (über 10 h, wird markiert).
            list.append(work(week, "08:00", "19:15"))
        }
        list.append(work(today, "08:00", nil))

        var result: [LocalDate: DayEntry] = [:]
        for entry in list {
            result[entry.date] = entry
        }
        return result
    }

    /// Setzt den eigenen Speicher für Bildschirmfotos zurück: Standardeinstellungen und, wenn
    /// `withEntries`, die Beispieldaten. Der echte Speicher wird nie angefasst.
    static func install(storage: WorkStorage, today: LocalDate, withEntries: Bool) {
        guard storage.isDemo else { return }
        storage.replaceEntries(withEntries ? entries(today: today) : [:])
        storage.saveSettings(AppSettings())
    }

    private static func work(_ date: LocalDate, _ start: String, _ end: String?, breakMinutes: Int = 0) -> DayEntry {
        return DayEntry(
            date: date,
            type: .work,
            start: LocalTime(iso: start),
            end: end.flatMap { LocalTime(iso: $0) },
            manualBreakMinutes: breakMinutes
        )
    }
}
