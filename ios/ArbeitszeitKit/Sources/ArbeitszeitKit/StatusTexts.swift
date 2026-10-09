// Status- und Teilen-Texte, wortgleich mit der Android-App.

/// Kurzer Wochenstatus, z. B. "Noch 7:30 h bis zur Grenze".
public func weekStatusText(_ summary: WeekSummary, isLimit: Bool) -> String {
    let balance = summary.balanceMinutes
    if isLimit && balance > 0 {
        return "Grenze um \(formatDuration(balance)) h überschritten"
    }
    if isLimit {
        return "Noch \(formatDuration(-balance)) h bis zur Grenze"
    }
    if balance < 0 {
        return "Noch \(formatDuration(-balance)) h offen"
    }
    return "+\(formatDuration(balance)) h Überstunden"
}

/// Text zum Tagesziel, z. B. "20 h voll um 18:45" oder "Tagessoll um 18:45".
/// `weekReached`: Die Wochenstunden sind inklusive der laufenden Zeit bereits erreicht.
public func goalText(_ goal: TodayGoal, settings: AppSettings, weekReached: Bool = false) -> String {
    let week = formatHoursInput(settings.weeklyTargetMinutes) + " h"
    switch goal {
    case .weekFull(let at):
        if !weekReached {
            return "\(week) voll um \(formatTime(at))"
        }
        if settings.weeklyHoursAreLimit {
            return "\(week) voll \u{2013} jetzt ausstempeln"
        }
        return "\(week) voll"
    case .weekAlreadyFull:
        if settings.weeklyHoursAreLimit {
            return "\(week) sind schon voll \u{2013} nicht weiterarbeiten"
        }
        return "\(week) sind schon voll"
    case .dailyTarget(let at):
        return "Tagessoll um \(formatTime(at))"
    }
}

/// Status von heute, z. B. "Seit 08:00 · 20 h voll um 18:45".
/// `otherDaysMinutes` sind die angerechneten Minuten der übrigen Tage dieser Woche.
public func todayStatusText(_ today: DayResult, otherDaysMinutes: Int, settings: AppSettings) -> String {
    let entry = today.entry
    if entry.type.isAbsence {
        return "Heute: \(entry.type.label)"
    }
    if let start = entry.start, entry.end == nil {
        var text = "Seit \(formatTime(start))"
        if let goal = WorkCalculator.todayGoal(entry: entry, otherDaysMinutes: otherDaysMinutes, settings: settings) {
            text += " \u{00B7} " + goalText(goal, settings: settings)
        }
        return text
    }
    if let start = entry.start, let end = entry.end {
        return "Heute \(formatTime(start))\u{2013}\(formatTime(end)) \u{00B7} \(formatDuration(today.creditedMinutes)) h"
    }
    return "Heute noch nicht eingestempelt"
}

/// Kurzbeschreibung der Pausenregeln, z. B. "mehr als 6 h → 30 min, mehr als 9 h → 45 min".
public func breakRulesText(_ settings: AppSettings) -> String {
    // Stabil nach Schwelle sortieren (wie sortedBy in Kotlin).
    let rules = settings.breakRules.enumerated()
        .filter { $0.element.breakMinutes > 0 }
        .sorted { lhs, rhs in
            if lhs.element.afterMinutes != rhs.element.afterMinutes {
                return lhs.element.afterMinutes < rhs.element.afterMinutes
            }
            return lhs.offset < rhs.offset
        }
        .map { $0.element }
    let parts = rules.map { rule -> String in
        "mehr als \(formatHoursInput(rule.afterMinutes)) h \u{2192} \(rule.breakMinutes) min"
    }
    return parts.joined(separator: ", ")
}

/// Hinweis unter der Wochenübersicht zum automatischen Pausenabzug.
public func breakInfoText(_ settings: AppSettings) -> String {
    if settings.autoBreak {
        return "Pausen werden automatisch abgezogen (\(breakRulesText(settings))). " +
            "Eine längere eingetragene Pause hat Vorrang."
    }
    return "Automatischer Pausenabzug ist ausgeschaltet. Es wird nur die eingetragene Pause abgezogen."
}

/// Zeile eines Tages im Teilen-Text, nil für Tage ohne Zeit.
private func shareDayLine(_ day: DayResult) -> String? {
    let entry = day.entry
    if entry.type.isAbsence {
        return "\(entry.type.label) \u{2192} \(formatDuration(day.creditedMinutes)) h"
    }
    if let start = entry.start, let end = entry.end {
        return "\(formatTime(start))\u{2013}\(formatTime(end)), Pause \(formatDuration(day.breakMinutes)) \u{2192} " +
            "\(formatDuration(day.creditedMinutes)) h"
    }
    if day.running, let start = entry.start {
        return "seit \(formatTime(start)) (läuft) \u{2192} \(formatDuration(day.creditedMinutes)) h"
    }
    return nil
}

/// Text zum Teilen einer Woche (z. B. per Mail oder Messenger).
public func weekShareText(_ summary: WeekSummary, isLimit: Bool) -> String {
    var text = "Arbeitszeit KW \(weekNumber(summary.weekStart)) (\(weekRange(summary.weekStart)))\n"
    text += "\n"
    for day in summary.days {
        if let line = shareDayLine(day) {
            text += "\(shortDayName(day.entry.date)) \(formatShortDate(day.entry.date)): \(line)\n"
        }
    }
    text += "\n"
    text += "Summe: \(formatDuration(summary.actualMinutes)) h\n"
    if isLimit {
        let balance = summary.balanceMinutes
        text += "Grenze: \(formatDuration(summary.targetMinutes)) h\n"
        if balance > 0 {
            text += "Grenze überschritten um: \(formatDuration(balance)) h\n"
        } else {
            text += "Bis zur Grenze: \(formatDuration(-balance)) h\n"
        }
    } else {
        text += "Soll: \(formatDuration(summary.targetMinutes)) h\n"
        text += "Saldo: \(formatBalance(summary.balanceMinutes)) h\n"
    }
    text += "Abgezogene Pausen: \(formatDuration(summary.breakMinutes)) h"
    return text
}

// MARK: - Tageskarte der Wochenansicht

/// Detailzeile eines Tages in der Wochenansicht mit der Art der Darstellung.
public struct DayDetail: Hashable, Sendable {
    public enum Tone: String, Hashable, Sendable {
        /// Urlaub, Krank, Feiertag (Android: tertiary)
        case absence
        /// Läuft gerade (Android: primary)
        case running
        /// Läuft und die Wochengrenze ist erreicht (Android: rot)
        case warning
        /// Normaler Text (Android: onSurfaceVariant)
        case normal
        /// Beginn oder Ende fehlt (Android: error)
        case error
    }

    public var text: String
    public var tone: Tone

    public init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }
}

/// Detailzeile eines Tages, z. B. "08:00 – 16:30 · Pause 0:30 h (auto)".
/// `weekReached`: Die Wochenstunden sind inklusive der laufenden Zeit bereits erreicht.
public func dayDetail(_ day: DayResult, settings: AppSettings, otherDaysMinutes: Int, weekReached: Bool) -> DayDetail {
    let entry = day.entry
    let breakText = "Pause \(formatDuration(day.breakMinutes)) h" + (day.autoBreakApplied ? " (auto)" : "")
    if entry.type.isAbsence {
        return DayDetail(text: "\(entry.type.label) \u{00B7} Tagessoll gutgeschrieben", tone: .absence)
    }
    if day.running, let start = entry.start {
        let goal = WorkCalculator.todayGoal(entry: entry, otherDaysMinutes: otherDaysMinutes, settings: settings)
        var goalLine = ""
        var warn = false
        if let goal = goal {
            goalLine = "\n" + goalText(goal, settings: settings, weekReached: weekReached)
            // Werkstudenten-Grenze erreicht: deutlich warnen.
            switch goal {
            case .weekAlreadyFull:
                warn = settings.weeklyHoursAreLimit
            case .weekFull:
                warn = settings.weeklyHoursAreLimit && weekReached
            case .dailyTarget:
                warn = false
            }
        }
        return DayDetail(text: "seit \(formatTime(start)) \u{00B7} \(breakText)\(goalLine)", tone: warn ? .warning : .running)
    }
    if let start = entry.start, let end = entry.end {
        return DayDetail(text: "\(formatTime(start)) \u{2013} \(formatTime(end)) \u{00B7} \(breakText)", tone: .normal)
    }
    if let start = entry.start {
        return DayDetail(text: "Beginn \(formatTime(start)) \u{00B7} Ende fehlt", tone: .error)
    }
    if let end = entry.end {
        return DayDetail(text: "Ende \(formatTime(end)) \u{00B7} Beginn fehlt", tone: .error)
    }
    return DayDetail(text: "Kein Eintrag \u{2013} tippen zum Erfassen", tone: .normal)
}

/// Stunden rechts auf der Tageskarte: "8:00 h" oder "–", wenn nichts zu zählen ist.
public func dayValueText(_ day: DayResult) -> String {
    let hasValue = day.creditedMinutes > 0 || (day.entry.start != nil && day.entry.end != nil)
    if hasValue || day.running {
        return "\(formatDuration(day.creditedMinutes)) h"
    }
    return "\u{2013}"
}
