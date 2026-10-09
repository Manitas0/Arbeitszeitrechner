/// Ergebnis für einen Tag.
public struct DayResult: Hashable, Sendable {
    public var entry: DayEntry
    /// Zeit zwischen Beginn und Ende (bzw. jetzt, wenn der Tag noch läuft).
    public var attendanceMinutes: Int
    public var breakMinutes: Int
    /// true, wenn mehr Pause abgezogen wurde als eingetragen.
    public var autoBreakApplied: Bool
    /// Angerechnete Minuten: Netto-Arbeitszeit oder Gutschrift bei Abwesenheit.
    public var creditedMinutes: Int
    /// Beginn gesetzt, Ende noch offen und der Tag ist heute.
    public var running: Bool

    public init(
        entry: DayEntry,
        attendanceMinutes: Int = 0,
        breakMinutes: Int = 0,
        autoBreakApplied: Bool = false,
        creditedMinutes: Int = 0,
        running: Bool = false
    ) {
        self.entry = entry
        self.attendanceMinutes = attendanceMinutes
        self.breakMinutes = breakMinutes
        self.autoBreakApplied = autoBreakApplied
        self.creditedMinutes = creditedMinutes
        self.running = running
    }

    /// Mehr Arbeitszeit als die gesetzliche Tageshöchstgrenze (§ 3 ArbZG).
    public var exceedsDailyMax: Bool {
        return !entry.type.isAbsence && creditedMinutes > WorkCalculator.maxDailyWorkMinutes
    }
}

/// Summen einer Woche (Montag bis Sonntag).
public struct WeekSummary: Hashable, Sendable {
    public var weekStart: LocalDate
    /// Ergebnisse von Montag bis Sonntag.
    public var days: [DayResult]
    public var actualMinutes: Int
    public var targetMinutes: Int
    public var breakMinutes: Int

    public init(weekStart: LocalDate, days: [DayResult], actualMinutes: Int, targetMinutes: Int, breakMinutes: Int) {
        self.weekStart = weekStart
        self.days = days
        self.actualMinutes = actualMinutes
        self.targetMinutes = targetMinutes
        self.breakMinutes = breakMinutes
    }

    public var balanceMinutes: Int {
        return actualMinutes - targetMinutes
    }

    /// Angerechnete Minuten aller anderen Tage der Woche (ohne `date`).
    public func minutesExcluding(_ date: LocalDate) -> Int {
        return days.filter { $0.entry.date != date }.reduce(0) { $0 + $1.creditedMinutes }
    }
}

/// Ziel für einen Arbeitstag, an dem gerade eingestempelt ist.
public enum TodayGoal: Hashable, Sendable {
    /// Die Wochenstunden sind heute um `at` voll.
    case weekFull(at: LocalTime)
    /// Die Wochenstunden sind schon durch die anderen Tage voll.
    case weekAlreadyFull
    /// Die Woche wird heute nicht voll (höchstens 10 h pro Tag); um `at` ist das Tagessoll erreicht.
    case dailyTarget(at: LocalTime)
}

/// Berechnung von Tages- und Wochenzeiten.
public enum WorkCalculator {

    /// § 3 ArbZG: höchstens 10 Stunden Arbeitszeit pro Tag.
    public static let maxDailyWorkMinutes: Int = 10 * 60

    /// Montag der Woche von `date`.
    public static func weekStartOf(_ date: LocalDate) -> LocalDate {
        return date.minusDays(date.dayOfWeek - 1)
    }

    /// Minuten von `start` bis `end`; liegt das Ende vor dem Beginn, geht die Schicht über Mitternacht.
    public static func attendanceMinutes(start: LocalTime, end: LocalTime) -> Int {
        let minutes = end.minutesOfDay - start.minutesOfDay
        return minutes < 0 ? minutes + 24 * 60 : minutes
    }

    /// Wertet einen Tag aus. Mit `now` zählt ein heute begonnener Tag ohne Ende bis jetzt mit.
    public static func evaluate(entry: DayEntry, settings: AppSettings, now: LocalDateTime? = nil) -> DayResult {
        if entry.type.isAbsence {
            return DayResult(entry: entry, creditedMinutes: settings.dailyTargetMinutes)
        }
        guard let start = entry.start else {
            return DayResult(entry: entry)
        }
        let attendance: Int
        var running = false
        if let end = entry.end {
            attendance = attendanceMinutes(start: start, end: end)
        } else if let now = now, now.date == entry.date {
            running = true
            // Sekunden spielen keine Rolle: Duration.toMinutes() schneidet ab.
            attendance = max(now.time.minutesOfDay - start.minutesOfDay, 0)
        } else {
            return DayResult(entry: entry)
        }
        let breakMinutes = BreakCalculator.deductedBreak(
            attendanceMinutes: attendance,
            manualBreakMinutes: entry.manualBreakMinutes,
            settings: settings
        )
        return DayResult(
            entry: entry,
            attendanceMinutes: attendance,
            breakMinutes: breakMinutes,
            autoBreakApplied: breakMinutes > entry.manualBreakMinutes,
            creditedMinutes: attendance - breakMinutes,
            running: running
        )
    }

    /// Wertet die Woche ab `weekStart` (Montag) aus. Fehlende Tage zählen als leer.
    public static func summarizeWeek(
        weekStart: LocalDate,
        entries: [LocalDate: DayEntry],
        settings: AppSettings,
        now: LocalDateTime? = nil
    ) -> WeekSummary {
        var days: [DayResult] = []
        for offset in 0..<7 {
            let date = weekStart.plusDays(offset)
            let entry = entries[date] ?? DayEntry(date: date)
            days.append(WorkCalculator.evaluate(entry: entry, settings: settings, now: now))
        }
        return WeekSummary(
            weekStart: weekStart,
            days: days,
            actualMinutes: days.reduce(0) { $0 + $1.creditedMinutes },
            targetMinutes: settings.weeklyTargetMinutes,
            breakMinutes: days.reduce(0) { $0 + $1.breakMinutes }
        )
    }

    /// Bis wann heute gearbeitet werden muss (bzw. darf): Lassen sich die restlichen Wochenstunden
    /// heute schaffen, zählt der Zeitpunkt, an dem die Woche voll ist – sonst das Tagessoll.
    /// `otherDaysMinutes` sind die angerechneten Minuten der übrigen Tage dieser Woche.
    public static func todayGoal(entry: DayEntry, otherDaysMinutes: Int, settings: AppSettings) -> TodayGoal? {
        guard let start = entry.start else {
            return nil
        }
        let remaining = settings.weeklyTargetMinutes - otherDaysMinutes
        if remaining <= 0 {
            return .weekAlreadyFull
        }
        if remaining <= maxDailyWorkMinutes {
            let end = endTimeForTarget(
                start: start,
                manualBreakMinutes: entry.manualBreakMinutes,
                targetMinutes: remaining,
                settings: settings
            )
            return .weekFull(at: end)
        }
        let end = endTimeForTarget(
            start: start,
            manualBreakMinutes: entry.manualBreakMinutes,
            targetMinutes: settings.dailyTargetMinutes,
            settings: settings
        )
        return .dailyTarget(at: end)
    }

    /// Uhrzeit, zu der bei Beginn um `start` die Sollzeit `targetMinutes` netto erreicht ist,
    /// inklusive der automatisch abgezogenen Pause.
    public static func endTimeForTarget(
        start: LocalTime,
        manualBreakMinutes: Int,
        targetMinutes: Int,
        settings: AppSettings
    ) -> LocalTime {
        var attendance = max(targetMinutes, 0)
        while attendance < targetMinutes + 24 * 60 {
            let deducted = BreakCalculator.deductedBreak(
                attendanceMinutes: attendance,
                manualBreakMinutes: manualBreakMinutes,
                settings: settings
            )
            if attendance - deducted >= targetMinutes {
                break
            }
            attendance += 1
        }
        return start.plusMinutes(attendance)
    }
}
