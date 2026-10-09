// Formatierung von Zeiten, Daten und Stunden – Zeichen für Zeichen wie in der Android-App.

private let germanDayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

private let germanMonthNames = [
    "Januar", "Februar", "März", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
]

/// 510 -> "8:30", -90 -> "−1:30" (mit dem Minuszeichen U+2212)
public func formatDuration(_ minutes: Int) -> String {
    let sign = minutes < 0 ? "\u{2212}" : ""
    let value = abs(minutes)
    return sign + String(value / 60) + ":" + pad2(value % 60)
}

/// Wie `formatDuration`, aber mit "+" bei positiven Werten.
public func formatBalance(_ minutes: Int) -> String {
    if minutes > 0 {
        return "+" + formatDuration(minutes)
    }
    return formatDuration(minutes)
}

/// "08:05"
public func formatTime(_ time: LocalTime) -> String {
    return pad2(time.hour) + ":" + pad2(time.minute)
}

/// Akzeptiert "40", "38,5", "38.5" und "38:30". Liefert Minuten oder nil.
public func parseHours(_ text: String) -> Int? {
    let trimmed = trimmedScalars(text.unicodeScalars)
    if trimmed.isEmpty {
        return nil
    }
    let colon: Unicode.Scalar = ":"
    if trimmed.contains(colon) {
        let parts = splitScalars(trimmed, separator: colon)
        if parts.count != 2 {
            return nil
        }
        guard let hours = kotlinToInt(trimmedScalars(parts[0])),
              let minutes = kotlinToInt(trimmedScalars(parts[1]))
        else { return nil }
        if hours < 0 || minutes < 0 || minutes > 59 {
            return nil
        }
        // Kotlin rechnet mit 32-Bit-Int.
        return Int(Int32(truncatingIfNeeded: hours * 60 + minutes))
    }
    let comma: Unicode.Scalar = ","
    let dot: Unicode.Scalar = "."
    let normalized = trimmed.map { (scalar: Unicode.Scalar) -> Unicode.Scalar in
        scalar == comma ? dot : scalar
    }
    guard let value = kotlinToDouble(normalized) else { return nil }
    if value < 0 || value.isNaN || value.isInfinite {
        return nil
    }
    return kotlinRoundToInt(value * 60)
}

/// Ganze Zahl wie Kotlins String.toIntOrNull() (ohne Leerzeichen, z. B. für "Arbeitstage pro Woche").
public func parseWholeNumber(_ text: String) -> Int? {
    return kotlinToInt(Array(text.unicodeScalars))
}

/// Behält nur Ziffern und höchstens `maxLength` Zeichen (wie `text.filter(Char::isDigit).take(n)`).
public func filterDigits(_ text: String, maxLength: Int) -> String {
    let digits = text.unicodeScalars.filter { decimalDigitValue($0) != nil }
    return makeString(digits.prefix(max(maxLength, 0)))
}

/// 480 -> "8", 510 -> "8,5", 505 -> "8:25"
public func formatHoursInput(_ minutes: Int) -> String {
    if minutes % 60 == 0 {
        return String(minutes / 60)
    }
    if minutes % 30 == 0 {
        return String(minutes / 60) + ",5"
    }
    return String(minutes / 60) + ":" + pad2(minutes % 60)
}

/// 615 -> "10,25" (Dezimalstunden mit zwei Nachkommastellen, z. B. für die Lohnabrechnung).
/// Negative Werte mit ASCII-Minus: -90 -> "-1,50".
public func formatDecimalHours(_ minutes: Int) -> String {
    let sign = minutes < 0 ? "-" : ""
    // Hundertstelstunden, kaufmännisch gerundet. Minuten/60 liegt nie genau auf x,xx5,
    // daher stimmt das mit String.format("%.2f") überein.
    let hundredths = (abs(minutes) * 100 + 30) / 60
    return sign + String(hundredths / 100) + "," + pad2(hundredths % 100)
}

/// "Montag" ... "Sonntag"
public func germanDayName(_ date: LocalDate) -> String {
    return germanDayNames[date.dayOfWeek - 1]
}

/// "Mo" ... "So"
public func shortDayName(_ date: LocalDate) -> String {
    return String(germanDayName(date).prefix(2))
}

/// "September 2026"
public func germanMonthName(_ month: YearMonth) -> String {
    return germanMonthNames[month.month - 1] + " " + String(month.year)
}

/// Kalenderwoche nach ISO 8601.
public func weekNumber(_ weekStart: LocalDate) -> Int {
    return weekStart.isoWeek
}

/// "28.09." (wie DateTimeFormatter "dd.MM.")
public func formatShortDate(_ date: LocalDate) -> String {
    return pad2(date.day) + "." + pad2(date.month) + "."
}

/// "28.09.2026" (wie DateTimeFormatter "dd.MM.yyyy")
public func formatLongDate(_ date: LocalDate) -> String {
    return pad2(date.day) + "." + pad2(date.month) + "." + pad4(date.year)
}

/// "28.09. – 04.10.2026"
public func weekRange(_ weekStart: LocalDate) -> String {
    return formatShortDate(weekStart) + " \u{2013} " + formatLongDate(weekStart.plusDays(6))
}
