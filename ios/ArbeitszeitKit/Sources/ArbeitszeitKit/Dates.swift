import Foundation

// Datum und Uhrzeit wie java.time (LocalDate, LocalTime, LocalDateTime, YearMonth).
// Gerechnet wird mit reinen Ganzzahl-Algorithmen im proleptischen gregorianischen Kalender,
// damit die Ergebnisse auf iOS, macOS und Linux exakt mit Android übereinstimmen.
// Calendar wird nur für "jetzt" und die Umrechnung von/zu Foundation.Date benutzt.

// MARK: - Kalenderrechnung

/// Ganzzahlige Division, die immer abrundet (auch bei negativen Zahlen).
func floorDiv(_ value: Int, _ divisor: Int) -> Int {
    let quotient = value / divisor
    if value % divisor != 0 && ((value < 0) != (divisor < 0)) {
        return quotient - 1
    }
    return quotient
}

/// Rest mit dem Vorzeichen des Teilers (wie Math.floorMod).
func floorMod(_ value: Int, _ divisor: Int) -> Int {
    return value - floorDiv(value, divisor) * divisor
}

func isLeapYear(_ year: Int) -> Bool {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 2:
        return isLeapYear(year) ? 29 : 28
    case 4, 6, 9, 11:
        return 30
    default:
        return 31
    }
}

/// Tage seit dem 01.01.1970 (Howard Hinnant, "days_from_civil").
func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
    let shiftedYear = month <= 2 ? year - 1 : year
    let era = floorDiv(shiftedYear, 400)
    let yearOfEra = shiftedYear - era * 400
    let shiftedMonth = (month + 9) % 12 // März = 0, Februar = 11
    let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}

/// Umkehrung von `daysFromCivil` ("civil_from_days").
func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
    let shifted = days + 719_468
    let era = floorDiv(shifted, 146_097)
    let dayOfEra = shifted - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shiftedMonth = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
    let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (year: year, month: month, day: day)
}

/// Gregorianischer Kalender in der Zeitzone des Geräts (auch wenn der Nutzer z. B. den
/// japanischen oder buddhistischen Kalender eingestellt hat).
func gregorianCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    return calendar
}

// MARK: - Text-Hilfen

/// Zweistellig mit führender Null wie "%02d".
func pad2(_ value: Int) -> String {
    if value >= 0 && value < 10 {
        return "0" + String(value)
    }
    return String(value)
}

/// Mindestens vierstellig mit führenden Nullen wie "%04d".
func pad4(_ value: Int) -> String {
    if value < 0 {
        return "-" + pad4(-value)
    }
    let digits = String(value)
    if digits.count >= 4 {
        return digits
    }
    return String(repeating: "0", count: 4 - digits.count) + digits
}

/// Liest genau `count` ASCII-Ziffern ab `start`.
func parseDigits(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int? {
    guard start >= 0, count > 0, start + count <= bytes.count else { return nil }
    var value = 0
    for index in start..<(start + count) {
        let byte = bytes[index]
        guard byte >= 0x30, byte <= 0x39 else { return nil }
        value = value * 10 + Int(byte - 0x30)
    }
    return value
}

/// Liest "YYYY-MM-DD" ab `start` (die Länge prüft der Aufrufer).
func parseIsoDate(_ bytes: [UInt8], from start: Int) -> LocalDate? {
    guard start >= 0, bytes.count >= start + 10,
          bytes[start + 4] == 0x2D, bytes[start + 7] == 0x2D,
          let year = parseDigits(bytes, start, 4),
          let month = parseDigits(bytes, start + 5, 2),
          let day = parseDigits(bytes, start + 8, 2),
          LocalDate.isValid(year: year, month: month, day: day)
    else { return nil }
    return LocalDate(year: year, month: month, day: day)
}

/// Liest "HH:mm", "HH:mm:ss" oder "HH:mm:ss.SSSSSSSSS" ab `start` bis zum Ende, so streng wie
/// LocalTime.parse. Sekundenbruchteile sind erlaubt, werden aber verworfen.
func parseIsoTime(_ bytes: [UInt8], from start: Int) -> (minutes: Int, seconds: Int)? {
    let length = bytes.count - start
    guard start >= 0, length >= 5, bytes[start + 2] == 0x3A,
          let hour = parseDigits(bytes, start, 2),
          let minute = parseDigits(bytes, start + 3, 2),
          hour <= 23, minute <= 59
    else { return nil }
    if length == 5 {
        return (minutes: hour * 60 + minute, seconds: 0)
    }
    guard length >= 8, bytes[start + 5] == 0x3A,
          let second = parseDigits(bytes, start + 6, 2),
          second <= 59
    else { return nil }
    if length == 8 {
        return (minutes: hour * 60 + minute, seconds: second)
    }
    guard bytes[start + 8] == 0x2E, length <= 18 else { return nil }
    for index in (start + 9)..<bytes.count {
        guard bytes[index] >= 0x30, bytes[index] <= 0x39 else { return nil }
    }
    return (minutes: hour * 60 + minute, seconds: second)
}

// MARK: - LocalDate

/// Kalenderdatum ohne Uhrzeit und Zeitzone (wie java.time.LocalDate).
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    /// 1 = Januar ... 12 = Dezember
    public let month: Int
    public let day: Int

    /// Erwartet ein gültiges Datum, siehe `isValid(year:month:day:)`.
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Datum aus den Tagen seit dem 01.01.1970.
    public init(epochDay: Int) {
        let civil = civilFromDays(epochDay)
        self.init(year: civil.year, month: civil.month, day: civil.day)
    }

    /// Liest "YYYY-MM-DD" (wie LocalDate.parse). Ungültige Daten wie "2026-02-30" ergeben nil.
    public init?(iso: String) {
        let bytes = Array(iso.utf8)
        guard bytes.count == 10, let date = parseIsoDate(bytes, from: 0) else { return nil }
        self = date
    }

    public static func isValid(year: Int, month: Int, day: Int) -> Bool {
        return month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(year: year, month: month)
    }

    /// Heutiges Datum in der Zeitzone des Geräts.
    public static func today() -> LocalDate {
        return LocalDateTime.now().date
    }

    /// Tage seit dem 01.01.1970.
    public var epochDay: Int {
        return daysFromCivil(year: year, month: month, day: day)
    }

    /// 1 = Montag ... 7 = Sonntag
    public var dayOfWeek: Int {
        // Der 01.01.1970 war ein Donnerstag.
        return floorMod(epochDay + 3, 7) + 1
    }

    /// Kalenderwoche nach ISO 8601 (die Woche mit dem Donnerstag bestimmt das Jahr).
    public var isoWeek: Int {
        let thursday = plusDays(4 - dayOfWeek)
        let firstOfYear = LocalDate(year: thursday.year, month: 1, day: 1)
        return (thursday.epochDay - firstOfYear.epochDay) / 7 + 1
    }

    /// Jahr, zu dem die ISO-Kalenderwoche gehört (z. B. 2026 für den 01.01.2027).
    public var weekBasedYear: Int {
        return plusDays(4 - dayOfWeek).year
    }

    public var lengthOfMonth: Int {
        return daysInMonth(year: year, month: month)
    }

    /// "YYYY-MM-DD"
    public var iso: String {
        return pad4(year) + "-" + pad2(month) + "-" + pad2(day)
    }

    public var description: String {
        return iso
    }

    public func plusDays(_ days: Int) -> LocalDate {
        return LocalDate(epochDay: epochDay + days)
    }

    public func minusDays(_ days: Int) -> LocalDate {
        return plusDays(-days)
    }

    public func plusWeeks(_ weeks: Int) -> LocalDate {
        return plusDays(weeks * 7)
    }

    public func minusWeeks(_ weeks: Int) -> LocalDate {
        return plusDays(-(weeks * 7))
    }

    /// Anzahl Tage bis `other` (negativ, wenn `other` davor liegt).
    public func daysUntil(_ other: LocalDate) -> Int {
        return other.epochDay - epochDay
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        return (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: - LocalTime

/// Uhrzeit auf die Minute genau (wie java.time.LocalTime ohne Sekunden).
public struct LocalTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Minuten seit Mitternacht (0...1439).
    public let minutesOfDay: Int

    /// Werte außerhalb eines Tages werden auf 0...1439 umgerechnet (1440 -> 00:00).
    public init(minutesOfDay: Int) {
        self.minutesOfDay = floorMod(minutesOfDay, 24 * 60)
    }

    public init(hour: Int, minute: Int) {
        self.init(minutesOfDay: hour * 60 + minute)
    }

    /// Liest "HH:mm" oder "HH:mm:ss" so streng wie LocalTime.parse ("8:00" oder "24:00" ergeben nil).
    /// Sekunden werden verworfen.
    public init?(iso: String) {
        guard let parsed = parseIsoTime(Array(iso.utf8), from: 0) else { return nil }
        self.init(minutesOfDay: parsed.minutes)
    }

    /// Aktuelle Uhrzeit (auf die Minute abgeschnitten) in der Zeitzone des Geräts.
    public static func now() -> LocalTime {
        return LocalDateTime.now().time
    }

    public var hour: Int {
        return minutesOfDay / 60
    }

    public var minute: Int {
        return minutesOfDay % 60
    }

    /// "HH:mm"
    public var iso: String {
        return pad2(hour) + ":" + pad2(minute)
    }

    public var description: String {
        return iso
    }

    /// Addiert Minuten und rechnet über Mitternacht weiter (23:30 + 60 -> 00:30).
    public func plusMinutes(_ minutes: Int) -> LocalTime {
        return LocalTime(minutesOfDay: minutesOfDay + minutes)
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        return lhs.minutesOfDay < rhs.minutesOfDay
    }
}

// MARK: - LocalDateTime

/// Datum mit Uhrzeit auf die Sekunde genau (wie java.time.LocalDateTime ohne Nanosekunden).
public struct LocalDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var date: LocalDate
    public var time: LocalTime
    /// 0...59
    public var seconds: Int

    public init(date: LocalDate, time: LocalTime, seconds: Int = 0) {
        self.date = date
        self.time = time
        self.seconds = min(max(seconds, 0), 59)
    }

    /// Liest "YYYY-MM-DDTHH:mm" oder "YYYY-MM-DDTHH:mm:ss" (wie LocalDateTime.parse).
    public init?(iso: String) {
        let bytes = Array(iso.utf8)
        guard bytes.count >= 16,
              bytes[10] == 0x54 || bytes[10] == 0x74, // "T" oder "t"
              let parsedDate = parseIsoDate(bytes, from: 0),
              let parsedTime = parseIsoTime(bytes, from: 11)
        else { return nil }
        self.init(date: parsedDate, time: LocalTime(minutesOfDay: parsedTime.minutes), seconds: parsedTime.seconds)
    }

    /// Umrechnung eines Zeitpunkts in Datum und Uhrzeit der Zeitzone des Geräts.
    public init(foundationDate: Date) {
        let components = gregorianCalendar().dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: foundationDate
        )
        self.init(
            date: LocalDate(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1),
            time: LocalTime(hour: components.hour ?? 0, minute: components.minute ?? 0),
            seconds: components.second ?? 0
        )
    }

    /// Jetzt in der Zeitzone des Geräts.
    public static func now() -> LocalDateTime {
        return LocalDateTime(foundationDate: Date())
    }

    /// Zeitpunkt in der Zeitzone des Geräts, z. B. für einen DatePicker.
    public var foundationDate: Date? {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = seconds
        return gregorianCalendar().date(from: components)
    }

    /// Wie LocalDateTime.toString(): "YYYY-MM-DDTHH:mm", mit ":ss" nur wenn die Sekunden nicht 0 sind.
    public var iso: String {
        let base = date.iso + "T" + time.iso
        if seconds > 0 {
            return base + ":" + pad2(seconds)
        }
        return base
    }

    public var description: String {
        return iso
    }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        if lhs.time != rhs.time {
            return lhs.time < rhs.time
        }
        return lhs.seconds < rhs.seconds
    }
}

// MARK: - YearMonth

/// Monat eines Jahres (wie java.time.YearMonth).
public struct YearMonth: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    /// 1 = Januar ... 12 = Dezember
    public let month: Int

    /// Monate außerhalb von 1...12 werden umgerechnet (Monat 13 -> Januar des Folgejahres).
    public init(year: Int, month: Int) {
        let total = year * 12 + (month - 1)
        self.year = floorDiv(total, 12)
        self.month = floorMod(total, 12) + 1
    }

    public init(_ date: LocalDate) {
        self.init(year: date.year, month: date.month)
    }

    public init(date: LocalDate) {
        self.init(year: date.year, month: date.month)
    }

    /// Liest "YYYY-MM".
    public init?(iso: String) {
        let bytes = Array(iso.utf8)
        guard bytes.count == 7, bytes[4] == 0x2D,
              let parsedYear = parseDigits(bytes, 0, 4),
              let parsedMonth = parseDigits(bytes, 5, 2),
              parsedMonth >= 1, parsedMonth <= 12
        else { return nil }
        self.init(year: parsedYear, month: parsedMonth)
    }

    /// Aktueller Monat in der Zeitzone des Geräts.
    public static func current() -> YearMonth {
        return YearMonth(LocalDate.today())
    }

    public var lengthOfMonth: Int {
        return daysInMonth(year: year, month: month)
    }

    public func atDay(_ day: Int) -> LocalDate {
        return LocalDate(year: year, month: month, day: day)
    }

    public func plusMonths(_ months: Int) -> YearMonth {
        return YearMonth(year: year, month: month + months)
    }

    public func minusMonths(_ months: Int) -> YearMonth {
        return plusMonths(-months)
    }

    /// "YYYY-MM"
    public var iso: String {
        return pad4(year) + "-" + pad2(month)
    }

    public var description: String {
        return iso
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        return (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}
