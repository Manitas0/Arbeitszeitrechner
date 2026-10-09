/// Gesetzliche Mindestpause und abgezogene Pause.
public enum BreakCalculator {

    /// Mindestpause in Minuten für eine Anwesenheit von `attendanceMinutes`.
    public static func requiredBreak(attendanceMinutes: Int, settings: AppSettings) -> Int {
        if !settings.autoBreak || attendanceMinutes <= 0 {
            return 0
        }
        let rules = settings.breakRules.filter { $0.breakMinutes > 0 }
        if settings.gradualDeduction {
            // Jede Regel ist erfüllt, wenn entweder die volle Pause gemacht wurde oder die
            // Arbeitszeit (Anwesenheit - Pause) die Schwelle nicht überschreitet.
            let breaks = rules.map { rule -> Int in
                min(rule.breakMinutes, max(attendanceMinutes - rule.afterMinutes, 0))
            }
            return breaks.max() ?? 0
        }
        let breaks = rules.filter { attendanceMinutes > $0.afterMinutes }.map { $0.breakMinutes }
        return breaks.max() ?? 0
    }

    /// Tatsächlich abgezogene Pause: die eingetragene Pause, aber mindestens die gesetzliche.
    public static func deductedBreak(attendanceMinutes: Int, manualBreakMinutes: Int, settings: AppSettings) -> Int {
        let manual = max(manualBreakMinutes, 0)
        let legal = requiredBreak(attendanceMinutes: attendanceMinutes, settings: settings)
        return min(max(manual, legal), max(attendanceMinutes, 0))
    }
}
