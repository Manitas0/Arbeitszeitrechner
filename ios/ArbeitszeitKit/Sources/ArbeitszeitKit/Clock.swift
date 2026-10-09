/// Was ein Tipp auf "Stempeln" (App, Widget, Kurzbefehl) gerade bewirkt.
public enum ClockAction: String, CaseIterable, Hashable, Sendable {
    case clockIn = "CLOCK_IN"
    case clockOut = "CLOCK_OUT"

    public var label: String {
        switch self {
        case .clockIn:
            return "Kommen"
        case .clockOut:
            return "Gehen"
        }
    }
}

/// nil: Heute ist schon fertig gestempelt oder ein Abwesenheitstag.
public func nextClockAction(_ entry: DayEntry) -> ClockAction? {
    if entry.type.isAbsence {
        return nil
    }
    if entry.start == nil {
        return .clockIn
    }
    if entry.end == nil {
        return .clockOut
    }
    return nil
}

/// Kommen setzt den Beginn (und löscht ein altes Ende), Gehen setzt das Ende.
public func applyClockAction(_ entry: DayEntry, action: ClockAction, time: LocalTime) -> DayEntry {
    var result = entry
    switch action {
    case .clockIn:
        result.type = .work
        result.start = time
        result.end = nil
    case .clockOut:
        result.end = time
    }
    return result
}

/// Führt die nächste Stempel-Aktion aus (wie TimeClock.toggle in Android).
/// Liefert die Aktion und den neuen Eintrag, oder nil, wenn nichts zu tun ist.
/// `time` ist die aktuelle Uhrzeit auf die Minute, z. B. `LocalTime.now()`.
public func toggleClock(_ entry: DayEntry, at time: LocalTime) -> (action: ClockAction, entry: DayEntry)? {
    guard let action = nextClockAction(entry) else { return nil }
    return (action: action, entry: applyClockAction(entry, action: action, time: time))
}
