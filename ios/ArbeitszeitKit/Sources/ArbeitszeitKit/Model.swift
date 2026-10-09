/// Art eines Tages. Die Rohwerte sind die Namen aus der Android-App (Sicherungsformat).
public enum DayType: String, CaseIterable, Hashable, Sendable, Identifiable {
    case work = "WORK"
    case vacation = "VACATION"
    case sick = "SICK"
    case holiday = "HOLIDAY"

    public var id: String {
        return rawValue
    }

    public var label: String {
        switch self {
        case .work:
            return "Arbeit"
        case .vacation:
            return "Urlaub"
        case .sick:
            return "Krank"
        case .holiday:
            return "Feiertag"
        }
    }

    /// Abwesenheitstage werden mit der täglichen Sollzeit gutgeschrieben.
    public var isAbsence: Bool {
        return self != .work
    }
}

/// Eintrag für einen Tag.
public struct DayEntry: Hashable, Sendable, Identifiable {
    public var date: LocalDate
    public var type: DayType
    public var start: LocalTime?
    public var end: LocalTime?
    /// Tatsächlich gemachte Pause in Minuten (optional).
    public var manualBreakMinutes: Int

    public init(
        date: LocalDate,
        type: DayType = .work,
        start: LocalTime? = nil,
        end: LocalTime? = nil,
        manualBreakMinutes: Int = 0
    ) {
        self.date = date
        self.type = type
        self.start = start
        self.end = end
        self.manualBreakMinutes = manualBreakMinutes
    }

    public var id: LocalDate {
        return date
    }

    /// Leere Einträge werden nicht gespeichert.
    public var isEmpty: Bool {
        return type == .work && start == nil && end == nil && manualBreakMinutes == 0
    }
}

/// Ab mehr als `afterMinutes` Arbeitszeit sind mindestens `breakMinutes` Pause vorgeschrieben.
public struct BreakRule: Hashable, Sendable {
    public var afterMinutes: Int
    public var breakMinutes: Int

    public init(afterMinutes: Int, breakMinutes: Int) {
        self.afterMinutes = afterMinutes
        self.breakMinutes = breakMinutes
    }
}

/// Einstellungen. Standard: Werkstudent mit 20 h an 2 Tagen pro Woche.
public struct AppSettings: Hashable, Sendable {
    public var weeklyTargetMinutes: Int
    public var workDaysPerWeek: Int
    /// true: Die Wochenstunden sind eine Obergrenze (z. B. 20-Stunden-Grenze für Werkstudenten).
    /// Mehrarbeit wird dann als Überschreitung gewarnt statt als Überstunden angezeigt.
    public var weeklyHoursAreLimit: Bool
    public var autoBreak: Bool
    /// true: Es wird nur so viel Pause abgezogen, dass die Arbeitszeit nicht unter die jeweilige
    /// Schwelle fällt (6:15 h Anwesenheit -> 6:00 h Arbeit), wie es § 4 ArbZG entspricht.
    /// false: Die volle Pause wird abgezogen, sobald die Anwesenheit die Schwelle überschreitet.
    public var gradualDeduction: Bool
    public var breakRules: [BreakRule]

    /// § 4 Arbeitszeitgesetz: > 6 h -> 30 min, > 9 h -> 45 min.
    public static let defaultBreakRules: [BreakRule] = [
        BreakRule(afterMinutes: 6 * 60, breakMinutes: 30),
        BreakRule(afterMinutes: 9 * 60, breakMinutes: 45),
    ]

    public init(
        weeklyTargetMinutes: Int = 20 * 60,
        workDaysPerWeek: Int = 2,
        weeklyHoursAreLimit: Bool = true,
        autoBreak: Bool = true,
        gradualDeduction: Bool = true,
        breakRules: [BreakRule] = AppSettings.defaultBreakRules
    ) {
        self.weeklyTargetMinutes = weeklyTargetMinutes
        self.workDaysPerWeek = workDaysPerWeek
        self.weeklyHoursAreLimit = weeklyHoursAreLimit
        self.autoBreak = autoBreak
        self.gradualDeduction = gradualDeduction
        self.breakRules = breakRules
    }

    /// Tagessoll: Wochenstunden geteilt durch die Arbeitstage (1 bis 7).
    public var dailyTargetMinutes: Int {
        return weeklyTargetMinutes / min(max(workDaysPerWeek, 1), 7)
    }
}
