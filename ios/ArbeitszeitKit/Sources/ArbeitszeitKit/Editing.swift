// Eingabelogik der Dialoge (Einstellungen, Tag bearbeiten) mit denselben Prüfungen wie Android.

private func validated(_ number: Int?, in range: ClosedRange<Int>) -> Int? {
    guard let number = number, range.contains(number) else { return nil }
    return number
}

/// Formularwerte der Einstellungen als Text, wie im Einstellungsbildschirm von Android.
public struct SettingsForm: Hashable, Sendable {
    public var weeklyText: String
    public var daysText: String
    public var weeklyHoursAreLimit: Bool
    public var autoBreak: Bool
    public var gradualDeduction: Bool
    public var rule1AfterText: String
    public var rule1BreakText: String
    public var rule2AfterText: String
    public var rule2BreakText: String

    public init(settings: AppSettings) {
        let rules = settings.breakRules.count >= 2 ? settings.breakRules : AppSettings.defaultBreakRules
        weeklyText = formatHoursInput(settings.weeklyTargetMinutes)
        daysText = String(settings.workDaysPerWeek)
        weeklyHoursAreLimit = settings.weeklyHoursAreLimit
        autoBreak = settings.autoBreak
        gradualDeduction = settings.gradualDeduction
        rule1AfterText = formatHoursInput(rules[0].afterMinutes)
        rule1BreakText = String(rules[0].breakMinutes)
        rule2AfterText = formatHoursInput(rules[1].afterMinutes)
        rule2BreakText = String(rules[1].breakMinutes)
    }

    /// Wochenarbeitszeit in Minuten (1 min bis 168 h) oder nil bei ungültiger Eingabe.
    public var weeklyMinutes: Int? {
        return validated(parseHours(weeklyText), in: 1...(7 * 24 * 60))
    }

    /// Arbeitstage pro Woche (1 bis 7) oder nil.
    public var workDays: Int? {
        return validated(parseWholeNumber(daysText), in: 1...7)
    }

    /// Schwelle der Stufe 1 in Minuten (0 bis 24 h) oder nil.
    public var rule1After: Int? {
        return validated(parseHours(rule1AfterText), in: 0...(24 * 60))
    }

    /// Pause der Stufe 1 in Minuten (0 bis 600) oder nil.
    public var rule1Break: Int? {
        return validated(parseWholeNumber(rule1BreakText), in: 0...600)
    }

    public var rule2After: Int? {
        return validated(parseHours(rule2AfterText), in: 0...(24 * 60))
    }

    public var rule2Break: Int? {
        return validated(parseWholeNumber(rule2BreakText), in: 0...600)
    }

    /// Beide Pausenregeln, wenn alle vier Felder gültig sind.
    public var breakRules: [BreakRule]? {
        guard let after1 = rule1After, let break1 = rule1Break,
              let after2 = rule2After, let break2 = rule2Break
        else { return nil }
        return [
            BreakRule(afterMinutes: after1, breakMinutes: break1),
            BreakRule(afterMinutes: after2, breakMinutes: break2),
        ]
    }

    /// Speichern ist möglich: Wochenstunden und Tage gültig, Pausenregeln nur bei automatischem Abzug nötig.
    public var isValid: Bool {
        return weeklyMinutes != nil && workDays != nil && (!autoBreak || breakRules != nil)
    }

    /// Hinweis unter dem Feld Wochenarbeitszeit.
    public var weeklyHint: String {
        guard let weekly = weeklyMinutes else {
            return "Bitte z. B. 40, 38,5 oder 38:30 eingeben"
        }
        return "Tagessoll: \(formatDuration(weekly / (workDays ?? 5))) h"
    }

    /// "Gesetzliche Werte wiederherstellen (§ 4 ArbZG)"
    public mutating func restoreLegalBreakRules() {
        let defaults = AppSettings.defaultBreakRules
        rule1AfterText = formatHoursInput(defaults[0].afterMinutes)
        rule1BreakText = String(defaults[0].breakMinutes)
        rule2AfterText = formatHoursInput(defaults[1].afterMinutes)
        rule2BreakText = String(defaults[1].breakMinutes)
        gradualDeduction = true
    }

    /// Neue Einstellungen oder nil, wenn das Formular ungültig ist. Sind die Pausenregeln
    /// ungültig (nur möglich bei ausgeschaltetem Abzug), bleiben `currentBreakRules` erhalten.
    public func makeSettings(currentBreakRules: [BreakRule]) -> AppSettings? {
        guard isValid, let weekly = weeklyMinutes, let days = workDays else { return nil }
        return AppSettings(
            weeklyTargetMinutes: weekly,
            workDaysPerWeek: days,
            weeklyHoursAreLimit: weeklyHoursAreLimit,
            autoBreak: autoBreak,
            gradualDeduction: gradualDeduction,
            breakRules: breakRules ?? currentBreakRules
        )
    }
}

/// Logik des Dialogs "Tag bearbeiten".
public enum DayEditing {

    /// Text für das Pausenfeld: leer, wenn keine Pause eingetragen ist.
    public static func breakText(for entry: DayEntry) -> String {
        return entry.manualBreakMinutes > 0 ? String(entry.manualBreakMinutes) : ""
    }

    /// Eintrag aus den Eingaben. Abwesenheitstage werden ohne Zeiten und Pause gespeichert.
    public static func draft(
        date: LocalDate,
        type: DayType,
        start: LocalTime?,
        end: LocalTime?,
        breakText: String
    ) -> DayEntry {
        if type == .work {
            let manualBreak = parseWholeNumber(breakText) ?? 0
            return DayEntry(date: date, type: type, start: start, end: end, manualBreakMinutes: manualBreak)
        }
        return DayEntry(date: date, type: type)
    }

    /// Vorschlag für den Beginn: heute die aktuelle Uhrzeit, sonst 08:00.
    public static func defaultStart(date: LocalDate, now: LocalDateTime) -> LocalTime {
        if date == now.date {
            return now.time
        }
        return LocalTime(hour: 8, minute: 0)
    }

    /// Vorschlag für das Ende: heute die aktuelle Uhrzeit, sonst das Ende für das Tagessoll.
    public static func defaultEnd(
        date: LocalDate,
        start: LocalTime?,
        manualBreakMinutes: Int,
        settings: AppSettings,
        now: LocalDateTime
    ) -> LocalTime {
        if date == now.date {
            return now.time
        }
        return WorkCalculator.endTimeForTarget(
            start: start ?? LocalTime(hour: 8, minute: 0),
            manualBreakMinutes: manualBreakMinutes,
            targetMinutes: settings.dailyTargetMinutes,
            settings: settings
        )
    }

    /// Hinweis unter dem Pausenfeld.
    public static func breakHint(settings: AppSettings) -> String {
        if settings.autoBreak {
            return "Mindestens die gesetzliche Pause wird automatisch abgezogen."
        }
        return "Automatischer Pausenabzug ist ausgeschaltet."
    }

    /// Text für Abwesenheitstage, z. B. "Urlaub: Es werden 10:00 h (Tagessoll) gutgeschrieben."
    public static func absenceText(type: DayType, settings: AppSettings) -> String {
        return "\(type.label): Es werden \(formatDuration(settings.dailyTargetMinutes)) h (Tagessoll) gutgeschrieben."
    }

    /// Titel des Dialogs, z. B. "Montag, 28.09.2026".
    public static func title(date: LocalDate) -> String {
        return germanDayName(date) + ", " + formatLongDate(date)
    }
}
