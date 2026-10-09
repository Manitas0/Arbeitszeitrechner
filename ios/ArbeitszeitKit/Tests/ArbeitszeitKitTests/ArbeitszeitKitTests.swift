import Foundation
import XCTest
@testable import ArbeitszeitKit

/// Handgeschriebene Tests, u. a. mit den Beispielen aus der README.
final class ArbeitszeitKitTests: XCTestCase {

    private let monday = LocalDate(year: 2026, month: 9, day: 28)
    private let student = AppSettings()

    private func t(_ hour: Int, _ minute: Int = 0) -> LocalTime {
        return LocalTime(hour: hour, minute: minute)
    }

    // MARK: - Berechnung

    func testDefaultsAreWorkingStudent() {
        XCTAssertEqual(student.weeklyTargetMinutes, 20 * 60)
        XCTAssertEqual(student.workDaysPerWeek, 2)
        XCTAssertEqual(student.dailyTargetMinutes, 10 * 60)
        XCTAssertTrue(student.weeklyHoursAreLimit)
        XCTAssertTrue(student.autoBreak)
        XCTAssertTrue(student.gradualDeduction)
        XCTAssertEqual(
            student.breakRules,
            [BreakRule(afterMinutes: 360, breakMinutes: 30), BreakRule(afterMinutes: 540, breakMinutes: 45)]
        )
        XCTAssertEqual(AppSettings(workDaysPerWeek: 0).dailyTargetMinutes, 20 * 60)
        XCTAssertEqual(AppSettings(workDaysPerWeek: 9).dailyTargetMinutes, 20 * 60 / 7)
    }

    /// README: "6:15 h anwesend → 15 min Pause → 6:00 h Arbeitszeit".
    func testGradualDeductionExample() {
        let entry = DayEntry(date: monday, start: t(8), end: t(14, 15))
        let gradual = WorkCalculator.evaluate(entry: entry, settings: student)
        XCTAssertEqual(gradual.attendanceMinutes, 375)
        XCTAssertEqual(gradual.breakMinutes, 15)
        XCTAssertEqual(gradual.creditedMinutes, 360)
        XCTAssertTrue(gradual.autoBreakApplied)

        // Ohne gestaffelten Abzug wird die volle Pause abgezogen.
        let flat = WorkCalculator.evaluate(entry: entry, settings: AppSettings(gradualDeduction: false))
        XCTAssertEqual(flat.breakMinutes, 30)
        XCTAssertEqual(flat.creditedMinutes, 345)

        // Eine längere eingetragene Pause hat Vorrang.
        var longBreak = entry
        longBreak.manualBreakMinutes = 60
        let manual = WorkCalculator.evaluate(entry: longBreak, settings: student)
        XCTAssertEqual(manual.breakMinutes, 60)
        XCTAssertFalse(manual.autoBreakApplied)
    }

    /// README: "Montag 10:30 h gearbeitet, Donnerstag ab 8:00 → „20 h voll um 18:15“".
    func testWeekFullExampleFromReadme() throws {
        let thursday = monday.plusDays(3)
        let running = DayEntry(date: thursday, start: t(8))
        let entries: [LocalDate: DayEntry] = [
            monday: DayEntry(date: monday, start: t(8), end: t(19, 15)), // 11:15 h - 0:45 h = 10:30 h
            thursday: running,
        ]
        let noon = LocalDateTime(date: thursday, time: t(12))
        let summary = WorkCalculator.summarizeWeek(weekStart: monday, entries: entries, settings: student, now: noon)
        XCTAssertEqual(summary.days[0].creditedMinutes, 630)
        XCTAssertTrue(summary.days[0].exceedsDailyMax)
        XCTAssertTrue(summary.days[3].running)

        let otherDays = summary.minutesExcluding(thursday)
        XCTAssertEqual(otherDays, 630)
        let goal = WorkCalculator.todayGoal(entry: running, otherDaysMinutes: otherDays, settings: student)
        XCTAssertEqual(goal, TodayGoal.weekFull(at: t(18, 15)))

        let today = WorkCalculator.evaluate(entry: running, settings: student)
        XCTAssertEqual(
            todayStatusText(today, otherDaysMinutes: otherDays, settings: student),
            "Seit 08:00 \u{00B7} 20 h voll um 18:15"
        )

        // Um 18:15 ist die Woche voll: rote Warnung.
        let evening = LocalDateTime(date: thursday, time: t(18, 15))
        let full = WorkCalculator.summarizeWeek(weekStart: monday, entries: entries, settings: student, now: evening)
        XCTAssertEqual(full.actualMinutes, 20 * 60)
        let weekReached = full.actualMinutes >= student.weeklyTargetMinutes
        XCTAssertTrue(weekReached)
        let unwrappedGoal = try XCTUnwrap(goal)
        XCTAssertEqual(
            goalText(unwrappedGoal, settings: student, weekReached: weekReached),
            "20 h voll \u{2013} jetzt ausstempeln"
        )
        let detail = dayDetail(full.days[3], settings: student, otherDaysMinutes: otherDays, weekReached: weekReached)
        XCTAssertEqual(detail.tone, DayDetail.Tone.warning)
        XCTAssertEqual(detail.text, "seit 08:00 \u{00B7} Pause 0:45 h (auto)\n20 h voll \u{2013} jetzt ausstempeln")
        XCTAssertEqual(weekStatusText(full, isLimit: true), "Noch 0:00 h bis zur Grenze")
    }

    /// Erster Arbeitstag: Die Woche wird heute nicht voll, also gilt das Tagessoll (10 h + 45 min Pause).
    func testFirstDayUsesDailyTarget() {
        let running = DayEntry(date: monday, start: t(8))
        XCTAssertEqual(
            WorkCalculator.todayGoal(entry: running, otherDaysMinutes: 0, settings: student),
            TodayGoal.dailyTarget(at: t(18, 45))
        )
        XCTAssertEqual(
            WorkCalculator.todayGoal(entry: running, otherDaysMinutes: 1200, settings: student),
            TodayGoal.weekAlreadyFull
        )
        XCTAssertEqual(
            goalText(TodayGoal.weekAlreadyFull, settings: student),
            "20 h sind schon voll \u{2013} nicht weiterarbeiten"
        )
        XCTAssertNil(WorkCalculator.todayGoal(entry: DayEntry(date: monday), otherDaysMinutes: 600, settings: student))
    }

    func testWorkingStudentWeekReachesLimitExactly() {
        let thursday = monday.plusDays(3)
        let entries: [LocalDate: DayEntry] = [
            monday: DayEntry(date: monday, start: t(8), end: t(18, 45)),
            thursday: DayEntry(date: thursday, start: t(9), end: t(19, 45)),
        ]
        let summary = WorkCalculator.summarizeWeek(weekStart: monday, entries: entries, settings: student)
        XCTAssertEqual(summary.actualMinutes, 20 * 60)
        XCTAssertEqual(summary.balanceMinutes, 0)
        XCTAssertEqual(summary.breakMinutes, 90)
        XCTAssertFalse(summary.days[0].exceedsDailyMax)
        XCTAssertEqual(weekStatusText(summary, isLimit: true), "Noch 0:00 h bis zur Grenze")
        XCTAssertEqual(weekStatusText(summary, isLimit: false), "+0:00 h Überstunden")
    }

    func testOvernightShiftAndDailyMaximum() {
        let night = WorkCalculator.evaluate(entry: DayEntry(date: monday, start: t(22), end: t(6)), settings: student)
        XCTAssertEqual(night.attendanceMinutes, 480)
        XCTAssertEqual(night.creditedMinutes, 450)

        let tooLong = WorkCalculator.evaluate(entry: DayEntry(date: monday, start: t(8), end: t(19)), settings: student)
        XCTAssertEqual(tooLong.creditedMinutes, 615)
        XCTAssertTrue(tooLong.exceedsDailyMax)

        let vacation = WorkCalculator.evaluate(
            entry: DayEntry(date: monday, type: .vacation),
            settings: AppSettings(weeklyTargetMinutes: 30 * 60)
        )
        XCTAssertEqual(vacation.creditedMinutes, 900)
        XCTAssertFalse(vacation.exceedsDailyMax)
    }

    func testRunningDayOnlyCountsToday() {
        let entry = DayEntry(date: monday, start: t(8))
        let today = WorkCalculator.evaluate(
            entry: entry,
            settings: student,
            now: LocalDateTime(date: monday, time: t(15), seconds: 59)
        )
        XCTAssertTrue(today.running)
        XCTAssertEqual(today.attendanceMinutes, 420)
        XCTAssertEqual(today.creditedMinutes, 390)

        let nextDay = WorkCalculator.evaluate(entry: entry, settings: student, now: LocalDateTime(date: monday.plusDays(1), time: t(10)))
        XCTAssertFalse(nextDay.running)
        XCTAssertEqual(nextDay.creditedMinutes, 0)

        let beforeStart = WorkCalculator.evaluate(entry: entry, settings: student, now: LocalDateTime(date: monday, time: t(7)))
        XCTAssertTrue(beforeStart.running)
        XCTAssertEqual(beforeStart.attendanceMinutes, 0)
    }

    // MARK: - Datum und Uhrzeit

    func testCalendarArithmetic() {
        let epoch = LocalDate(year: 1970, month: 1, day: 1)
        XCTAssertEqual(epoch.epochDay, 0)
        XCTAssertEqual(epoch.dayOfWeek, 4)
        XCTAssertEqual(LocalDate(epochDay: 0), epoch)
        XCTAssertEqual(LocalDate(year: 2000, month: 3, day: 1).epochDay, 11_017)
        XCTAssertEqual(LocalDate(epochDay: -1), LocalDate(year: 1969, month: 12, day: 31))
        XCTAssertEqual(monday.dayOfWeek, 1)
        XCTAssertEqual(monday.plusDays(6).dayOfWeek, 7)
        XCTAssertEqual(WorkCalculator.weekStartOf(LocalDate(year: 2026, month: 10, day: 4)), monday)
        XCTAssertEqual(monday.minusWeeks(1), LocalDate(year: 2026, month: 9, day: 21))
        XCTAssertEqual(monday.plusWeeks(1), LocalDate(year: 2026, month: 10, day: 5))
        XCTAssertEqual(monday.daysUntil(LocalDate(year: 2026, month: 10, day: 5)), 7)

        XCTAssertTrue(LocalDate.isValid(year: 2000, month: 2, day: 29))
        XCTAssertTrue(LocalDate.isValid(year: 2028, month: 2, day: 29))
        XCTAssertFalse(LocalDate.isValid(year: 1900, month: 2, day: 29))
        XCTAssertFalse(LocalDate.isValid(year: 2026, month: 2, day: 29))
        XCTAssertFalse(LocalDate.isValid(year: 2026, month: 13, day: 1))

        XCTAssertEqual(LocalDate(year: 2026, month: 1, day: 1).isoWeek, 1)
        XCTAssertEqual(LocalDate(year: 2015, month: 12, day: 31).isoWeek, 53)
        XCTAssertEqual(LocalDate(year: 2027, month: 1, day: 1).isoWeek, 53)
        XCTAssertEqual(LocalDate(year: 2027, month: 1, day: 1).weekBasedYear, 2026)
        XCTAssertEqual(LocalDate(year: 2024, month: 12, day: 30).isoWeek, 1)
        XCTAssertEqual(LocalDate(year: 2024, month: 12, day: 30).weekBasedYear, 2025)

        // Tag für Tag von 1899 bis 2101: lückenlos, gültig, Wochentage und Kalenderwochen stimmen.
        var date = LocalDate(year: 1899, month: 12, day: 25)
        var weekday = date.dayOfWeek
        for _ in 0..<(202 * 366) {
            let next = date.plusDays(1)
            weekday = weekday % 7 + 1
            let sameMonth = next.year == date.year && next.month == date.month && next.day == date.day + 1
            let newMonth = next.day == 1 && date.day == date.lengthOfMonth &&
                ((next.month == date.month + 1 && next.year == date.year) ||
                    (next.month == 1 && date.month == 12 && next.year == date.year + 1))
            if !(sameMonth || newMonth) {
                XCTFail("Kein Folgetag: \(date) -> \(next)")
                return
            }
            if next.epochDay != date.epochDay + 1 || next.dayOfWeek != weekday || LocalDate(iso: next.iso) != next {
                XCTFail("Falsche Tageszählung bei \(next)")
                return
            }
            // Kalenderwoche unabhängig berechnet: Woche 1 beginnt am Montag der Woche mit dem 4. Januar.
            let firstWeekMonday = WorkCalculator.weekStartOf(LocalDate(year: next.weekBasedYear, month: 1, day: 4))
            let expectedWeek = firstWeekMonday.daysUntil(WorkCalculator.weekStartOf(next)) / 7 + 1
            if next.isoWeek != expectedWeek {
                XCTFail("Kalenderwoche \(next.isoWeek) statt \(expectedWeek) für \(next)")
                return
            }
            date = next
        }
    }

    func testTimeParsingIsStrictLikeJava() {
        XCTAssertEqual(LocalTime(iso: "08:00"), t(8))
        XCTAssertEqual(LocalTime(iso: "23:59"), t(23, 59))
        XCTAssertEqual(LocalTime(iso: "00:00"), t(0))
        XCTAssertEqual(LocalTime(iso: "08:00:30"), t(8))
        XCTAssertEqual(LocalTime(iso: "08:00:30.123"), t(8))
        XCTAssertNil(LocalTime(iso: "8:00"))
        XCTAssertNil(LocalTime(iso: "24:00"))
        XCTAssertNil(LocalTime(iso: "08:60"))
        XCTAssertNil(LocalTime(iso: "08:00:60"))
        XCTAssertNil(LocalTime(iso: "08-00"))
        XCTAssertNil(LocalTime(iso: " 08:00"))
        XCTAssertNil(LocalTime(iso: ""))
        XCTAssertEqual(t(23, 30).plusMinutes(60), t(0, 30))
        XCTAssertEqual(t(0, 15).plusMinutes(-30), t(23, 45))
        XCTAssertEqual(t(9, 5).iso, "09:05")
        XCTAssertTrue(t(8) < t(8, 1))

        XCTAssertEqual(LocalDate(iso: "2026-09-28"), monday)
        XCTAssertNil(LocalDate(iso: "2026-02-30"))
        XCTAssertNil(LocalDate(iso: "2026-9-28"))
        XCTAssertNil(LocalDate(iso: "kaputt"))
        XCTAssertNil(LocalDate(iso: ""))

        XCTAssertEqual(LocalDateTime(iso: "2026-09-30T14:55:12")?.iso, "2026-09-30T14:55:12")
        XCTAssertEqual(LocalDateTime(iso: "2026-09-30T08:00:00")?.iso, "2026-09-30T08:00")
        XCTAssertEqual(LocalDateTime(iso: "2026-09-30T08:00")?.iso, "2026-09-30T08:00")
        XCTAssertNil(LocalDateTime(iso: "gestern"))
        XCTAssertNil(LocalDateTime(iso: "2026-09-30 08:00"))
        XCTAssertTrue(
            LocalDateTime(date: monday, time: t(8), seconds: 1) > LocalDateTime(date: monday, time: t(8))
        )
    }

    func testFoundationDateRoundtrip() throws {
        let local = LocalDateTime(date: LocalDate(year: 2026, month: 6, day: 15), time: t(12, 34), seconds: 56)
        let instant = try XCTUnwrap(local.foundationDate)
        XCTAssertEqual(LocalDateTime(foundationDate: instant), local)
    }

    func testYearMonth() {
        let january = YearMonth(year: 2027, month: 1)
        XCTAssertEqual(january.minusMonths(1), YearMonth(year: 2026, month: 12))
        XCTAssertEqual(january.plusMonths(13), YearMonth(year: 2028, month: 2))
        XCTAssertEqual(YearMonth(year: 2028, month: 2).lengthOfMonth, 29)
        XCTAssertEqual(YearMonth(year: 2026, month: 2).lengthOfMonth, 28)
        XCTAssertEqual(YearMonth(iso: "2026-09"), YearMonth(year: 2026, month: 9))
        XCTAssertNil(YearMonth(iso: "2026-13"))
        XCTAssertEqual(YearMonth(year: 2026, month: 9).iso, "2026-09")
        XCTAssertEqual(YearMonth(year: 2026, month: 9).atDay(30), LocalDate(year: 2026, month: 9, day: 30))
        XCTAssertEqual(YearMonth(monday), YearMonth(date: monday))
        XCTAssertEqual(germanMonthName(YearMonth(year: 2026, month: 3)), "März 2026")
        XCTAssertEqual(MonthExport.fileName(month: YearMonth(year: 2026, month: 9)), "Arbeitszeit-2026-09.csv")
        XCTAssertEqual(MonthExport.title(month: YearMonth(year: 2026, month: 9)), "Stundenzettel September 2026")
    }

    // MARK: - Formatierung

    func testFormatting() {
        XCTAssertEqual(formatDuration(510), "8:30")
        XCTAssertEqual(formatDuration(-90), "\u{2212}1:30")
        XCTAssertEqual(formatBalance(15), "+0:15")
        XCTAssertEqual(formatBalance(0), "0:00")
        XCTAssertEqual(formatHoursInput(2310), "38,5")
        XCTAssertEqual(formatHoursInput(2400), "40")
        XCTAssertEqual(formatHoursInput(468), "7:48")
        XCTAssertEqual(formatDecimalHours(615), "10,25")
        XCTAssertEqual(formatDecimalHours(-90), "-1,50")
        XCTAssertEqual(weekRange(monday), "28.09. \u{2013} 04.10.2026")
        XCTAssertEqual(shortDayName(monday), "Mo")
        XCTAssertEqual(formatShortDate(monday), "28.09.")
        XCTAssertEqual(formatLongDate(monday), "28.09.2026")
        XCTAssertEqual(
            breakInfoText(student),
            "Pausen werden automatisch abgezogen (mehr als 6 h \u{2192} 30 min, mehr als 9 h \u{2192} 45 min). " +
                "Eine längere eingetragene Pause hat Vorrang."
        )
    }

    func testParseHoursLikeKotlin() {
        XCTAssertEqual(parseHours("40"), 2400)
        XCTAssertEqual(parseHours("38,5"), 2310)
        XCTAssertEqual(parseHours("38.5"), 2310)
        XCTAssertEqual(parseHours("38:30"), 2310)
        XCTAssertEqual(parseHours(" 7 : 05 "), 425)
        XCTAssertEqual(parseHours("+1:30"), 90)
        XCTAssertEqual(parseHours(".5"), 30)
        XCTAssertEqual(parseHours("5."), 300)
        XCTAssertEqual(parseHours("1e1"), 600)
        // Kotlins toIntOrNull akzeptiert Unicode-Ziffern, toDoubleOrNull nicht.
        XCTAssertEqual(parseHours("\u{0661}:\u{0663}\u{0660}"), 90)
        XCTAssertNil(parseHours("\u{0661}\u{0662}"))
        XCTAssertNil(parseHours("abc"))
        XCTAssertNil(parseHours("8:75"))
        XCTAssertNil(parseHours("1:-5"))
        XCTAssertNil(parseHours("-5"))
        XCTAssertNil(parseHours("NaN"))
        XCTAssertNil(parseHours("Infinity"))
        XCTAssertNil(parseHours("."))
        XCTAssertNil(parseHours("1,2,3"))

        XCTAssertEqual(parseWholeNumber("5"), 5)
        XCTAssertEqual(parseWholeNumber("-5"), -5)
        XCTAssertNil(parseWholeNumber(" 5"))
        XCTAssertNil(parseWholeNumber("99999999999"))
        XCTAssertEqual(filterDigits("1a2b3c4", maxLength: 3), "123")
        XCTAssertEqual(filterDigits("abc", maxLength: 3), "")
    }

    // MARK: - Texte

    func testDayDetailTexts() {
        let complete = WorkCalculator.evaluate(entry: DayEntry(date: monday, start: t(8), end: t(16, 30)), settings: student)
        XCTAssertEqual(
            dayDetail(complete, settings: student, otherDaysMinutes: 0, weekReached: false),
            DayDetail(text: "08:00 \u{2013} 16:30 \u{00B7} Pause 0:30 h (auto)", tone: .normal)
        )
        XCTAssertEqual(dayValueText(complete), "8:00 h")

        let empty = WorkCalculator.evaluate(entry: DayEntry(date: monday), settings: student)
        XCTAssertEqual(dayValueText(empty), "\u{2013}")
        XCTAssertEqual(
            dayDetail(empty, settings: student, otherDaysMinutes: 0, weekReached: false).text,
            "Kein Eintrag \u{2013} tippen zum Erfassen"
        )

        let startOnly = WorkCalculator.evaluate(entry: DayEntry(date: monday, start: t(8)), settings: student)
        XCTAssertEqual(
            dayDetail(startOnly, settings: student, otherDaysMinutes: 0, weekReached: false),
            DayDetail(text: "Beginn 08:00 \u{00B7} Ende fehlt", tone: .error)
        )

        let endOnly = WorkCalculator.evaluate(entry: DayEntry(date: monday, end: t(16)), settings: student)
        XCTAssertEqual(
            dayDetail(endOnly, settings: student, otherDaysMinutes: 0, weekReached: false),
            DayDetail(text: "Ende 16:00 \u{00B7} Beginn fehlt", tone: .error)
        )

        let vacation = WorkCalculator.evaluate(entry: DayEntry(date: monday, type: .vacation), settings: student)
        XCTAssertEqual(
            dayDetail(vacation, settings: student, otherDaysMinutes: 0, weekReached: false),
            DayDetail(text: "Urlaub \u{00B7} Tagessoll gutgeschrieben", tone: .absence)
        )
        XCTAssertEqual(dayValueText(vacation), "10:00 h")

        let running = WorkCalculator.evaluate(
            entry: DayEntry(date: monday, start: t(8)),
            settings: student,
            now: LocalDateTime(date: monday, time: t(9))
        )
        XCTAssertEqual(
            dayDetail(running, settings: student, otherDaysMinutes: 0, weekReached: false),
            DayDetail(text: "seit 08:00 \u{00B7} Pause 0:00 h\nTagessoll um 18:45", tone: .running)
        )
        XCTAssertEqual(dayValueText(running), "1:00 h")
    }

    func testClockToggle() throws {
        let empty = DayEntry(date: monday, manualBreakMinutes: 15)
        let first = try XCTUnwrap(toggleClock(empty, at: t(8, 3)))
        XCTAssertEqual(first.action, ClockAction.clockIn)
        XCTAssertEqual(first.entry.start, t(8, 3))
        XCTAssertNil(first.entry.end)
        XCTAssertEqual(first.entry.manualBreakMinutes, 15)

        let second = try XCTUnwrap(toggleClock(first.entry, at: t(18, 50)))
        XCTAssertEqual(second.action, ClockAction.clockOut)
        XCTAssertEqual(second.entry.start, t(8, 3))
        XCTAssertEqual(second.entry.end, t(18, 50))

        XCTAssertNil(toggleClock(second.entry, at: t(19)))
        XCTAssertNil(toggleClock(DayEntry(date: monday, type: .holiday), at: t(9)))
        XCTAssertEqual(ClockAction.clockIn.label, "Kommen")
        XCTAssertEqual(ClockAction.clockOut.label, "Gehen")
        XCTAssertEqual(ClockAction.clockIn.rawValue, "CLOCK_IN")
    }

    // MARK: - Eingaben

    func testSettingsForm() {
        var form = SettingsForm(settings: AppSettings())
        XCTAssertEqual(form.weeklyText, "20")
        XCTAssertEqual(form.daysText, "2")
        XCTAssertEqual(form.rule1AfterText, "6")
        XCTAssertEqual(form.rule1BreakText, "30")
        XCTAssertEqual(form.rule2AfterText, "9")
        XCTAssertEqual(form.rule2BreakText, "45")
        XCTAssertEqual(form.weeklyHint, "Tagessoll: 10:00 h")
        XCTAssertTrue(form.isValid)
        XCTAssertEqual(form.makeSettings(currentBreakRules: []), AppSettings())

        form.weeklyText = "38,5"
        form.daysText = "5"
        XCTAssertEqual(form.weeklyHint, "Tagessoll: 7:42 h")
        XCTAssertEqual(form.makeSettings(currentBreakRules: [])?.weeklyTargetMinutes, 2310)

        form.weeklyText = "abc"
        XCTAssertFalse(form.isValid)
        XCTAssertEqual(form.weeklyHint, "Bitte z. B. 40, 38,5 oder 38:30 eingeben")
        XCTAssertNil(form.makeSettings(currentBreakRules: []))

        form.weeklyText = "40"
        form.daysText = "8"
        XCTAssertFalse(form.isValid)
        form.daysText = "5"
        form.rule2BreakText = "999"
        XCTAssertFalse(form.isValid)
        form.autoBreak = false
        XCTAssertTrue(form.isValid)
        let current = [BreakRule(afterMinutes: 300, breakMinutes: 20), BreakRule(afterMinutes: 540, breakMinutes: 0)]
        XCTAssertEqual(form.makeSettings(currentBreakRules: current)?.breakRules, current)

        form.restoreLegalBreakRules()
        XCTAssertEqual(form.rule2BreakText, "45")
        XCTAssertEqual(form.makeSettings(currentBreakRules: current)?.breakRules, AppSettings.defaultBreakRules)
    }

    func testDayEditing() {
        XCTAssertEqual(DayEditing.title(date: monday), "Montag, 28.09.2026")
        XCTAssertEqual(
            DayEditing.draft(date: monday, type: .vacation, start: t(8), end: t(9), breakText: "15"),
            DayEntry(date: monday, type: .vacation)
        )
        XCTAssertEqual(
            DayEditing.draft(date: monday, type: .work, start: t(8), end: nil, breakText: "15"),
            DayEntry(date: monday, start: t(8), manualBreakMinutes: 15)
        )
        XCTAssertEqual(
            DayEditing.draft(date: monday, type: .work, start: nil, end: nil, breakText: ""),
            DayEntry(date: monday)
        )
        XCTAssertEqual(DayEditing.breakText(for: DayEntry(date: monday)), "")
        XCTAssertEqual(DayEditing.breakText(for: DayEntry(date: monday, manualBreakMinutes: 20)), "20")
        let tomorrow = LocalDateTime(date: monday.plusDays(1), time: t(7))
        XCTAssertEqual(DayEditing.defaultStart(date: monday, now: tomorrow), t(8))
        XCTAssertEqual(
            DayEditing.defaultEnd(date: monday, start: nil, manualBreakMinutes: 0, settings: student, now: tomorrow),
            t(18, 45)
        )
        let now = LocalDateTime(date: monday, time: t(7, 12), seconds: 40)
        XCTAssertEqual(DayEditing.defaultStart(date: monday, now: now), t(7, 12))
        XCTAssertEqual(
            DayEditing.absenceText(type: .sick, settings: student),
            "Krank: Es werden 10:00 h (Tagessoll) gutgeschrieben."
        )
    }

    // MARK: - JSON und Sicherung

    func testJSONParser() {
        let text = "{\"a\": \"x\\u2013y\\ud83d\\ude00\\n\\/\", \"b\": [1, 2.5, -3e2, true, false, null], \"c\": {}}"
        let json = JSONParser.parse(text)
        XCTAssertEqual(json?["a"]?.stringValue, "x\u{2013}y\u{1F600}\n/")
        XCTAssertEqual(json?["b"]?.arrayValue?.count, 6)
        XCTAssertEqual(json?["b"]?.arrayValue?[1].intValue, 2)
        XCTAssertEqual(json?["b"]?.arrayValue?[2].intValue, -300)
        XCTAssertEqual(json?["b"]?.arrayValue?[3].boolValue, true)
        XCTAssertEqual(json?["b"]?.arrayValue?[5].isNull, true)
        XCTAssertEqual(json?["c"]?.isObject, true)

        XCTAssertNil(JSONParser.parse("{\"a\": 1} rest"))
        XCTAssertNotNil(JSONParser.parse("{\"a\": 1} rest", allowTrailingContent: true))
        XCTAssertNil(JSONParser.parse("{\"a\": 1,}"))
        XCTAssertNil(JSONParser.parse("[01]"))
        XCTAssertNil(JSONParser.parse("\"offen"))
        XCTAssertNil(JSONParser.parse(""))

        let special = "\"\\\n\u{1}ä\u{2013}"
        let serialized = JSONValue.object([JSONMember("s", .string(special))]).serialized()
        XCTAssertEqual(JSONParser.parse(serialized)?["s"]?.stringValue, special)
    }

    func testOrgJSONLeniency() {
        let parsed = JSONParser.parse(
            "{\"i\": \"30\", \"d\": 7.9, \"b\": \"TRUE\", \"n\": null, \"x\": true, \"s\": 5}"
        )
        XCTAssertNotNil(parsed)
        guard let json = parsed else { return }
        XCTAssertEqual(json.optInt("i", 0), 30)
        XCTAssertEqual(json.optInt("d", 0), 7)
        XCTAssertEqual(json.optInt("x", 4), 4)
        XCTAssertEqual(json.optInt("fehlt", 4), 4)
        XCTAssertEqual(json.optBoolean("b", false), true)
        XCTAssertEqual(json.optBoolean("i", true), true)
        XCTAssertEqual(json.optString("n"), "")
        XCTAssertEqual(json.optString("s"), "5")
        XCTAssertEqual(json.optString("fehlt"), "")
        XCTAssertNil(json.optArray("i"))
        XCTAssertNil(json.optObject("i"))
    }

    func testBackupRoundtripAndRestore() throws {
        let entries = [
            DayEntry(date: monday, start: t(8), end: t(16, 30)),
            DayEntry(date: monday.plusDays(1), type: .vacation),
            DayEntry(date: monday.plusDays(2)), // leer: wird nicht gesichert
        ]
        let settings = AppSettings(weeklyTargetMinutes: 38 * 60 + 30, workDaysPerWeek: 5, weeklyHoursAreLimit: false)
        let createdAt = LocalDateTime(date: monday, time: t(14, 55), seconds: 12)
        let text = BackupFormat.create(entries: entries.reversed(), settings: settings, createdAt: createdAt)
        XCTAssertTrue(text.contains("\"app\": \"Arbeitszeitrechner\""))

        let data = try BackupFormat.parse(text)
        XCTAssertEqual(data.createdAt, createdAt)
        XCTAssertEqual(data.settings, settings)
        XCTAssertEqual(data.entries, [entries[0], entries[1]])

        // Mit BOM und Resten einer längeren alten Datei (Android kürzt nicht bei jedem Anbieter).
        XCTAssertEqual(try BackupFormat.parse("\u{FEFF}" + text + "\n  ]\n}"), data)

        XCTAssertThrowsError(try BackupFormat.parse("{\"app\": \"Etwas anderes\"}")) { error in
            XCTAssertEqual(error as? BackupError, BackupError.notABackup)
        }

        let existing: [LocalDate: DayEntry] = [
            monday: DayEntry(date: monday, type: .sick),
            monday.plusDays(2): DayEntry(date: monday.plusDays(2), start: t(7)),
            monday.plusDays(4): DayEntry(date: monday.plusDays(4), start: t(9), end: t(12)),
        ]
        let merged = BackupFormat.merge(existing: existing, restored: entries)
        XCTAssertEqual(merged[monday], entries[0])
        XCTAssertEqual(merged[monday.plusDays(1)], entries[1])
        XCTAssertNil(merged[monday.plusDays(2)]) // leerer Eintrag löscht den Tag
        XCTAssertEqual(merged[monday.plusDays(4)], existing[monday.plusDays(4)])
        XCTAssertEqual(merged.count, 3)

        let restored = data.restore(into: existing, settings: AppSettings())
        XCTAssertEqual(restored.settings, settings)
        XCTAssertEqual(restored.entries.count, 4)
        XCTAssertEqual(restored.entries[monday.plusDays(2)], existing[monday.plusDays(2)])

        let withoutSettings = BackupData(createdAt: nil, settings: nil, entries: [])
        XCTAssertEqual(withoutSettings.restore(into: existing, settings: student).settings, student)
    }

    func testStorageRoundtrip() {
        let entries = [
            DayEntry(date: monday, start: t(8), end: t(16, 30), manualBreakMinutes: 40),
            DayEntry(date: monday.plusDays(2), type: .holiday),
            DayEntry(date: monday.plusDays(3)),
        ]
        let text = BackupFormat.encodeEntries(entries)
        let decoded = BackupFormat.decodeEntries(text)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[monday], entries[0])
        XCTAssertEqual(decoded[monday.plusDays(2)], entries[1])
        XCTAssertTrue(BackupFormat.decodeEntries("kaputt").isEmpty)
        XCTAssertEqual(
            BackupFormat.decodeEntries("{\"2026-09-28\": {\"start\": \"08:00\"}, \"x\": {}, \"2026-09-29\": {\"start\": \"25:00\"}}"),
            [monday: DayEntry(date: monday, start: t(8))]
        )

        let settings = AppSettings(weeklyTargetMinutes: 2400, workDaysPerWeek: 5, weeklyHoursAreLimit: false, gradualDeduction: false)
        XCTAssertEqual(BackupFormat.decodeSettings(BackupFormat.encodeSettings(settings)), settings)
        XCTAssertNil(BackupFormat.decodeSettings("[]"))
        XCTAssertEqual(BackupFormat.decodeSettings("{}"), AppSettings())

        let entry = DayEntry(date: monday, start: t(8), manualBreakMinutes: 15)
        XCTAssertEqual(BackupFormat.encodeEntryText(entry), "{\"type\":\"WORK\",\"start\":\"08:00\",\"break\":15}")
        XCTAssertEqual(BackupFormat.decodeEntryText(date: monday, text: BackupFormat.encodeEntryText(entry)), entry)
        XCTAssertNil(BackupFormat.decodeEntryText(date: monday, text: "{\"start\": \"25:00\"}"))
    }

    func testEntryDictionary() throws {
        let entry = DayEntry(date: monday, start: t(7, 30), end: t(16), manualBreakMinutes: 20)
        let json = BackupFormat.encodeEntry(entry)
        XCTAssertEqual(json["type"] as? String, "WORK")
        XCTAssertEqual(json["start"] as? String, "07:30")
        XCTAssertEqual(json["end"] as? String, "16:00")
        XCTAssertEqual(json["break"] as? Int, 20)
        XCTAssertNil(json["date"])
        XCTAssertEqual(try BackupFormat.decodeEntry(date: monday, json: json), entry)

        let absence = BackupFormat.encodeEntry(DayEntry(date: monday, type: .sick))
        XCTAssertNil(absence["start"])
        XCTAssertNil(absence["end"])
        XCTAssertEqual(absence["type"] as? String, "SICK")

        // Nachsicht wie org.json: unbekannte Art -> Arbeit, Pause als Text, negative Pause -> 0.
        let lenient: [String: Any] = ["type": "UNBEKANNT", "start": "", "break": "-5"]
        XCTAssertEqual(try BackupFormat.decodeEntry(date: monday, json: lenient), DayEntry(date: monday))
        let fractional: [String: Any] = ["type": "SICK", "break": 30.9]
        XCTAssertEqual(
            try BackupFormat.decodeEntry(date: monday, json: fractional),
            DayEntry(date: monday, type: .sick, manualBreakMinutes: 30)
        )
        XCTAssertThrowsError(try BackupFormat.decodeEntry(date: monday, json: ["start": "8 Uhr"]))
    }
}
