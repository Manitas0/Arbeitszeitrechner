import Foundation
import XCTest
@testable import ArbeitszeitKit

/// Fehler beim Lesen der Testfälle.
private struct VectorError: Error, CustomStringConvertible {
    let description: String
}

private extension JSONValue {
    func field(_ key: String) throws -> JSONValue {
        guard let value = self[key] else {
            throw VectorError(description: "Feld \"\(key)\" fehlt in \(serialized())")
        }
        return value
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let value = try field(key).intValue else {
            throw VectorError(description: "Feld \"\(key)\" ist keine Zahl in \(serialized())")
        }
        return value
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = try field(key).stringValue else {
            throw VectorError(description: "Feld \"\(key)\" ist kein Text in \(serialized())")
        }
        return value
    }

    func requiredBool(_ key: String) throws -> Bool {
        guard let value = try field(key).boolValue else {
            throw VectorError(description: "Feld \"\(key)\" ist kein Wahrheitswert in \(serialized())")
        }
        return value
    }

    func requiredArray(_ key: String) throws -> [JSONValue] {
        guard let value = try field(key).arrayValue else {
            throw VectorError(description: "Feld \"\(key)\" ist keine Liste in \(serialized())")
        }
        return value
    }

    /// Zweiteiliger Eintrag wie [eingabe, erwartet].
    func pair() throws -> (JSONValue, JSONValue) {
        guard let items = arrayValue, items.count == 2 else {
            throw VectorError(description: "Erwartet [a, b], gefunden \(serialized())")
        }
        return (items[0], items[1])
    }
}

/// Prüft die Swift-Implementierung gegen shared/test-vectors.json, das aus der Kotlin-Implementierung
/// (Android) erzeugt wird. Jeder Abschnitt und jeder Fall wird geprüft.
final class SharedVectorsTests: XCTestCase {

    private static var cachedVectors: JSONValue?

    private func vectors() throws -> JSONValue {
        if let cached = SharedVectorsTests.cachedVectors {
            return cached
        }
        // #filePath: <Repo>/ios/ArbeitszeitKit/Tests/ArbeitszeitKitTests/SharedVectorsTests.swift
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url = url.deletingLastPathComponent()
        }
        url = url.appendingPathComponent("shared").appendingPathComponent("test-vectors.json")
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        guard let json = JSONParser.parse(text) else {
            throw VectorError(description: "\(url.path) ist kein gültiges JSON")
        }
        SharedVectorsTests.cachedVectors = json
        return json
    }

    private func allSettings() throws -> [String: AppSettings] {
        var result: [String: AppSettings] = [:]
        let members = try vectors().field("settings").objectMembers ?? []
        for member in members {
            result[member.key] = BackupFormat.decodeSettingsValue(member.value)
        }
        return result
    }

    private func lookupSettings(_ name: String, _ all: [String: AppSettings]) throws -> AppSettings {
        guard let settings = all[name] else {
            throw VectorError(description: "Unbekannte Einstellungen \"\(name)\"")
        }
        return settings
    }

    private func decodeVectorEntry(_ json: JSONValue) throws -> DayEntry {
        guard let date = LocalDate(iso: json.optString("date")) else {
            throw VectorError(description: "Ungültiges Datum in \(json.serialized())")
        }
        return try BackupFormat.decodeEntryValue(date: date, json: json)
    }

    private func decodeEntryMap(_ items: [JSONValue]) throws -> [LocalDate: DayEntry] {
        var result: [LocalDate: DayEntry] = [:]
        for item in items {
            let decoded = try decodeVectorEntry(item)
            result[decoded.date] = decoded
        }
        return result
    }

    private func optionalNow(_ json: JSONValue) throws -> LocalDateTime? {
        guard let text = json["now"]?.stringValue else {
            return nil
        }
        guard let now = LocalDateTime(iso: text) else {
            throw VectorError(description: "Ungültiges now: \(text)")
        }
        return now
    }

    private func assertResult(_ actual: DayResult, _ expected: JSONValue, _ context: String) throws {
        let attendance = try expected.requiredInt("attendanceMinutes")
        let breakMinutes = try expected.requiredInt("breakMinutes")
        let autoBreakApplied = try expected.requiredBool("autoBreakApplied")
        let credited = try expected.requiredInt("creditedMinutes")
        let running = try expected.requiredBool("running")
        let exceeds = try expected.requiredBool("exceedsDailyMax")
        XCTAssertEqual(actual.attendanceMinutes, attendance, "attendanceMinutes – \(context)")
        XCTAssertEqual(actual.breakMinutes, breakMinutes, "breakMinutes – \(context)")
        XCTAssertEqual(actual.autoBreakApplied, autoBreakApplied, "autoBreakApplied – \(context)")
        XCTAssertEqual(actual.creditedMinutes, credited, "creditedMinutes – \(context)")
        XCTAssertEqual(actual.running, running, "running – \(context)")
        XCTAssertEqual(actual.exceedsDailyMax, exceeds, "exceedsDailyMax – \(context)")
    }

    private func describeGoal(_ goal: TodayGoal?) -> String {
        guard let goal = goal else {
            return "null"
        }
        switch goal {
        case .weekFull(let at):
            return "weekFull@" + formatTime(at)
        case .weekAlreadyFull:
            return "weekAlreadyFull"
        case .dailyTarget(let at):
            return "dailyTarget@" + formatTime(at)
        }
    }

    private func describeExpectedGoal(_ json: JSONValue) -> String {
        if json.isNull {
            return "null"
        }
        let kind = json.optString("kind")
        let at = json.optString("at")
        return at.isEmpty ? kind : kind + "@" + at
    }

    /// Zeigt bei abweichenden mehrzeiligen Texten die erste abweichende Zeile.
    private func assertText(_ actual: String, _ expected: String, _ context: String) {
        if actual == expected {
            return
        }
        let actualLines = actual.components(separatedBy: "\n")
        let expectedLines = expected.components(separatedBy: "\n")
        var detail = "Zeilenzahl \(actualLines.count) statt \(expectedLines.count)"
        for index in 0..<min(actualLines.count, expectedLines.count) where actualLines[index] != expectedLines[index] {
            detail = "Zeile \(index + 1): \"\(actualLines[index])\" statt \"\(expectedLines[index])\""
            break
        }
        XCTFail("\(context): \(detail)\n--- Swift ---\n\(actual)\n--- Kotlin ---\n\(expected)")
    }

    // MARK: - Einstellungen

    func testSettingsDecodeToKotlinValues() throws {
        let all = try allSettings()
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all["werkstudent"], AppSettings())
        XCTAssertEqual(
            all["vollzeit"],
            AppSettings(weeklyTargetMinutes: 40 * 60, workDaysPerWeek: 5, weeklyHoursAreLimit: false)
        )
        XCTAssertEqual(all["pauschal"], AppSettings(gradualDeduction: false))
        XCTAssertEqual(all["ohnePause"], AppSettings(autoBreak: false))
        XCTAssertEqual(
            all["eigeneRegeln"],
            AppSettings(
                weeklyTargetMinutes: 38 * 60 + 30,
                workDaysPerWeek: 5,
                weeklyHoursAreLimit: false,
                breakRules: [
                    BreakRule(afterMinutes: 5 * 60, breakMinutes: 20),
                    BreakRule(afterMinutes: 9 * 60, breakMinutes: 0),
                ]
            )
        )
        // Die Swift-Kodierung ergibt dasselbe JSON wie Kotlin.
        let members = try vectors().field("settings").objectMembers ?? []
        for member in members {
            let settings = try lookupSettings(member.key, all)
            XCTAssertTrue(
                BackupFormat.settingsValue(settings).isSemanticallyEqual(to: member.value),
                "settings.\(member.key): \(BackupFormat.encodeSettings(settings)) statt \(member.value.serialized())"
            )
        }
    }

    // MARK: - Pausen

    func testBreaks() throws {
        let all = try allSettings()
        let cases = try vectors().requiredArray("breaks")
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let name = try item.requiredString("settings")
            let settings = try lookupSettings(name, all)
            let attendance = try item.requiredInt("attendance")
            let manual = try item.requiredInt("manual")
            let expectedRequired = try item.requiredInt("required")
            let deducted = try item.requiredInt("deducted")
            let context = "breaks[\(index)] settings=\(name) attendance=\(attendance) manual=\(manual)"
            XCTAssertEqual(
                BreakCalculator.requiredBreak(attendanceMinutes: attendance, settings: settings),
                expectedRequired,
                "required – \(context)"
            )
            XCTAssertEqual(
                BreakCalculator.deductedBreak(attendanceMinutes: attendance, manualBreakMinutes: manual, settings: settings),
                deducted,
                "deducted – \(context)"
            )
        }
    }

    // MARK: - Tage

    func testDays() throws {
        let all = try allSettings()
        let cases = try vectors().requiredArray("days")
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let name = try item.requiredString("settings")
            let settings = try lookupSettings(name, all)
            let entryJSON = try item.field("entry")
            let entry = try decodeVectorEntry(entryJSON)
            let now = try optionalNow(item)
            let nowText = now?.iso ?? "-"
            let context = "days[\(index)] settings=\(name) entry=\(entryJSON.serialized()) now=\(nowText)"
            let result = WorkCalculator.evaluate(entry: entry, settings: settings, now: now)
            try assertResult(result, item.field("result"), context)
        }
    }

    // MARK: - Wochen

    func testWeeks() throws {
        let all = try allSettings()
        let cases = try vectors().requiredArray("weeks")
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let name = try item.requiredString("settings")
            let settings = try lookupSettings(name, all)
            let caseNumber = try item.requiredInt("case")
            let weekStartText = try item.requiredString("weekStart")
            let weekStart = try XCTUnwrap(LocalDate(iso: weekStartText), "weeks[\(index)] weekStart")
            let entries = try decodeEntryMap(item.requiredArray("entries"))
            let now = try optionalNow(item)
            let nowText = now?.iso ?? "-"
            let context = "weeks[\(index)] settings=\(name) case=\(caseNumber) now=\(nowText)"

            let summary = WorkCalculator.summarizeWeek(weekStart: weekStart, entries: entries, settings: settings, now: now)
            let expectedDays = try item.requiredArray("days")
            XCTAssertEqual(summary.days.count, expectedDays.count, "Anzahl Tage – \(context)")
            for (dayIndex, expectedDay) in expectedDays.enumerated() where dayIndex < summary.days.count {
                XCTAssertEqual(summary.days[dayIndex].entry.date, weekStart.plusDays(dayIndex), "Datum Tag \(dayIndex) – \(context)")
                try assertResult(summary.days[dayIndex], expectedDay, "Tag \(dayIndex) – \(context)")
            }

            let actual = try item.requiredInt("actualMinutes")
            let target = try item.requiredInt("targetMinutes")
            let breaks = try item.requiredInt("breakMinutes")
            let balance = try item.requiredInt("balanceMinutes")
            let excludingTuesday = try item.requiredInt("minutesExcludingTuesday")
            XCTAssertEqual(summary.actualMinutes, actual, "actualMinutes – \(context)")
            XCTAssertEqual(summary.targetMinutes, target, "targetMinutes – \(context)")
            XCTAssertEqual(summary.breakMinutes, breaks, "breakMinutes – \(context)")
            XCTAssertEqual(summary.balanceMinutes, balance, "balanceMinutes – \(context)")
            XCTAssertEqual(summary.minutesExcluding(weekStart.plusDays(1)), excludingTuesday, "minutesExcludingTuesday – \(context)")

            let statusLimit = try item.requiredString("weekStatusLimit")
            let statusNoLimit = try item.requiredString("weekStatusNoLimit")
            let shareLimit = try item.requiredString("shareTextLimit")
            let shareNoLimit = try item.requiredString("shareTextNoLimit")
            assertText(weekStatusText(summary, isLimit: true), statusLimit, "weekStatusLimit – \(context)")
            assertText(weekStatusText(summary, isLimit: false), statusNoLimit, "weekStatusNoLimit – \(context)")
            assertText(weekShareText(summary, isLimit: true), shareLimit, "shareTextLimit – \(context)")
            assertText(weekShareText(summary, isLimit: false), shareNoLimit, "shareTextNoLimit – \(context)")
        }
    }

    // MARK: - Tagesziel und Statustexte

    func testGoals() throws {
        let all = try allSettings()
        let cases = try vectors().requiredArray("goals")
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let name = try item.requiredString("settings")
            let settings = try lookupSettings(name, all)
            let entryJSON = try item.field("entry")
            let entry = try decodeVectorEntry(entryJSON)
            let otherDays = try item.requiredInt("otherDaysMinutes")
            let context = "goals[\(index)] settings=\(name) entry=\(entryJSON.serialized()) otherDaysMinutes=\(otherDays)"

            let goal = WorkCalculator.todayGoal(entry: entry, otherDaysMinutes: otherDays, settings: settings)
            XCTAssertEqual(describeGoal(goal), describeExpectedGoal(try item.field("goal")), "goal – \(context)")
            if let goal = goal {
                let text = try item.requiredString("text")
                let textReached = try item.requiredString("textReached")
                XCTAssertEqual(goalText(goal, settings: settings), text, "text – \(context)")
                XCTAssertEqual(goalText(goal, settings: settings, weekReached: true), textReached, "textReached – \(context)")
            } else {
                XCTAssertNil(item["text"], "text – \(context)")
                XCTAssertNil(item["textReached"], "textReached – \(context)")
            }
            let status = todayStatusText(
                WorkCalculator.evaluate(entry: entry, settings: settings),
                otherDaysMinutes: otherDays,
                settings: settings
            )
            XCTAssertEqual(status, try item.requiredString("todayStatus"), "todayStatus – \(context)")
        }
    }

    // MARK: - Endzeit

    func testEndTimes() throws {
        let all = try allSettings()
        let cases = try vectors().requiredArray("endTimes")
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let name = try item.requiredString("settings")
            let settings = try lookupSettings(name, all)
            let startText = try item.requiredString("start")
            let manual = try item.requiredInt("manual")
            let target = try item.requiredInt("target")
            let expected = try item.requiredString("end")
            let context = "endTimes[\(index)] settings=\(name) start=\(startText) manual=\(manual) target=\(target)"
            let start = try XCTUnwrap(LocalTime(iso: startText), context)
            let end = WorkCalculator.endTimeForTarget(
                start: start,
                manualBreakMinutes: manual,
                targetMinutes: target,
                settings: settings
            )
            XCTAssertEqual(formatTime(end), expected, context)
        }
    }

    // MARK: - Formatierung

    private func checkMinuteTexts(_ pairs: [JSONValue], _ label: String, _ function: (Int) -> String) throws {
        XCTAssertFalse(pairs.isEmpty, label)
        for (index, item) in pairs.enumerated() {
            let (input, output) = try item.pair()
            guard let minutes = input.intValue, let expected = output.stringValue else {
                throw VectorError(description: "format.\(label)[\(index)]: unerwartetes Format \(item.serialized())")
            }
            XCTAssertEqual(function(minutes), expected, "format.\(label)[\(index)] minutes=\(minutes)")
        }
    }

    func testFormat() throws {
        let format = try vectors().field("format")
        try checkMinuteTexts(format.requiredArray("duration"), "duration", formatDuration)
        try checkMinuteTexts(format.requiredArray("balance"), "balance", formatBalance)
        try checkMinuteTexts(format.requiredArray("hoursInput"), "hoursInput", formatHoursInput)
        try checkMinuteTexts(format.requiredArray("decimalHours"), "decimalHours", formatDecimalHours)

        let parseCases = try format.requiredArray("parseHours")
        XCTAssertFalse(parseCases.isEmpty)
        for (index, item) in parseCases.enumerated() {
            let (input, output) = try item.pair()
            guard let text = input.stringValue else {
                throw VectorError(description: "format.parseHours[\(index)]: unerwartetes Format \(item.serialized())")
            }
            let expected: Int? = output.isNull ? nil : output.intValue
            XCTAssertEqual(parseHours(text), expected, "format.parseHours[\(index)] input=\"\(text)\"")
        }

        let timeCases = try format.requiredArray("time")
        XCTAssertFalse(timeCases.isEmpty)
        for (index, item) in timeCases.enumerated() {
            let (input, output) = try item.pair()
            guard let iso = input.stringValue, let expected = output.stringValue else {
                throw VectorError(description: "format.time[\(index)]: unerwartetes Format \(item.serialized())")
            }
            let time = try XCTUnwrap(LocalTime(iso: iso), "format.time[\(index)] iso=\(iso)")
            XCTAssertEqual(formatTime(time), expected, "format.time[\(index)] iso=\(iso)")
            XCTAssertEqual(time.iso, iso, "format.time[\(index)] iso=\(iso)")
        }
    }

    // MARK: - Datum

    func testDates() throws {
        let cases = try vectors().requiredArray("dates")
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let dateText = try item.requiredString("date")
            let context = "dates[\(index)] date=\(dateText)"
            let date = try XCTUnwrap(LocalDate(iso: dateText), context)
            let weekStart = WorkCalculator.weekStartOf(date)
            XCTAssertEqual(date.iso, dateText, context)
            XCTAssertEqual(weekStart.iso, try item.requiredString("weekStart"), "weekStart – \(context)")
            XCTAssertEqual(weekNumber(date), try item.requiredInt("isoWeek"), "isoWeek – \(context)")
            XCTAssertEqual(date.isoWeek, try item.requiredInt("isoWeek"), "isoWeek – \(context)")
            XCTAssertEqual(weekRange(weekStart), try item.requiredString("weekRange"), "weekRange – \(context)")
            XCTAssertEqual(germanDayName(date), try item.requiredString("dayName"), "dayName – \(context)")
            XCTAssertEqual(germanMonthName(YearMonth(date)), try item.requiredString("monthName"), "monthName – \(context)")
        }
    }

    func testBreakRulesText() throws {
        let all = try allSettings()
        let cases = try vectors().requiredArray("breakRulesText")
        XCTAssertEqual(cases.count, all.count)
        for (index, item) in cases.enumerated() {
            let (nameJSON, textJSON) = try item.pair()
            guard let name = nameJSON.stringValue, let expected = textJSON.stringValue else {
                throw VectorError(description: "breakRulesText[\(index)]: unerwartetes Format \(item.serialized())")
            }
            let settings = try lookupSettings(name, all)
            XCTAssertEqual(breakRulesText(settings), expected, "breakRulesText[\(index)] settings=\(name)")
        }
    }

    // MARK: - Stempeln

    func testClock() throws {
        let cases = try vectors().requiredArray("clock")
        XCTAssertFalse(cases.isEmpty)
        let time = LocalTime(hour: 12, minute: 34)
        for (index, item) in cases.enumerated() {
            let entryJSON = try item.field("entry")
            let entry = try decodeVectorEntry(entryJSON)
            let context = "clock[\(index)] entry=\(entryJSON.serialized())"
            let next = nextClockAction(entry)
            let expectedNext = try item.field("next")
            XCTAssertEqual(next?.rawValue, expectedNext.stringValue, "next – \(context)")
            if let next = next {
                let appliedJSON = try item.field("applied")
                let expected = try decodeVectorEntry(appliedJSON)
                let applied = applyClockAction(entry, action: next, time: time)
                XCTAssertEqual(applied, expected, "applied – \(context)")
                XCTAssertTrue(
                    BackupFormat.entryValue(applied, includeDate: true).isSemanticallyEqual(to: appliedJSON),
                    "applied JSON – \(context)"
                )
            } else {
                XCTAssertNil(item["applied"], "applied – \(context)")
            }
        }
    }

    // MARK: - Monatsexport

    func testCSV() throws {
        let all = try allSettings()
        let cases = try vectors().requiredArray("csv")
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let name = try item.requiredString("settings")
            let settings = try lookupSettings(name, all)
            let monthText = try item.requiredString("month")
            let context = "csv[\(index)] settings=\(name) month=\(monthText)"
            let month = try XCTUnwrap(YearMonth(iso: monthText), context)
            XCTAssertEqual(month.iso, monthText, context)
            let entries = try decodeEntryMap(item.requiredArray("entries"))

            XCTAssertEqual(MonthExport.fileName(month: month), try item.requiredString("fileName"), "fileName – \(context)")
            XCTAssertEqual(germanMonthName(month), try item.requiredString("monthName"), "monthName – \(context)")

            let csv = MonthExport.csv(month: month, entries: entries, settings: settings)
            let expectedCSV = try item.requiredString("csv")
            XCTAssertEqual(csv.unicodeScalars.first?.value, 0xFEFF, "BOM – \(context)")
            XCTAssertTrue(csv.hasSuffix("\r\n"), "Zeilenende – \(context)")
            assertText(csv, expectedCSV, "csv – \(context)")
            XCTAssertEqual(Array(csv.utf8), Array(expectedCSV.utf8), "csv Bytes – \(context)")

            let summary = MonthExport.summary(month: month, entries: entries, settings: settings)
            let expectedSummary = try item.field("summary")
            XCTAssertEqual(summary.workedMinutes, try expectedSummary.requiredInt("workedMinutes"), "workedMinutes – \(context)")
            XCTAssertEqual(summary.absenceMinutes, try expectedSummary.requiredInt("absenceMinutes"), "absenceMinutes – \(context)")
            XCTAssertEqual(summary.workDays, try expectedSummary.requiredInt("workDays"), "workDays – \(context)")
            XCTAssertEqual(summary.absenceDays, try expectedSummary.requiredInt("absenceDays"), "absenceDays – \(context)")
            XCTAssertEqual(summary.totalMinutes, try expectedSummary.requiredInt("totalMinutes"), "totalMinutes – \(context)")
        }
    }

    // MARK: - Sicherung

    func testBackupCreate() throws {
        let all = try allSettings()
        let create = try vectors().field("backup").field("create")
        let entries = try create.requiredArray("entries").map { try decodeVectorEntry($0) }
        let settingsName = try create.requiredString("settings")
        let settings = try lookupSettings(settingsName, all)
        let createdAtText = try create.requiredString("createdAt")
        let createdAt = try XCTUnwrap(LocalDateTime(iso: createdAtText), "backup.create createdAt")
        XCTAssertEqual(createdAt.iso, createdAtText)
        let kotlinText = try create.requiredString("text")

        // Swift erzeugt dasselbe JSON wie Kotlin (Schlüsselreihenfolge und Einrückung egal).
        let swiftText = BackupFormat.create(entries: entries, settings: settings, createdAt: createdAt)
        let swiftJSON = try XCTUnwrap(JSONParser.parse(swiftText), "backup.create: Swift-Ausgabe ist kein JSON")
        let kotlinJSON = try XCTUnwrap(JSONParser.parse(kotlinText), "backup.create: Kotlin-Text ist kein JSON")
        XCTAssertTrue(
            swiftJSON.isSemanticallyEqual(to: kotlinJSON),
            "backup.create: Swift-Ausgabe weicht ab\n--- Swift ---\n\(swiftText)\n--- Kotlin ---\n\(kotlinText)"
        )

        // Roundtrip: Swift liest die eigene Sicherung.
        let expectedEntries = entries.filter { !$0.isEmpty }.sorted { $0.date < $1.date }
        let parsed = try BackupFormat.parse(swiftText)
        XCTAssertEqual(parsed.createdAt, createdAt, "backup.create Roundtrip createdAt")
        XCTAssertEqual(parsed.settings, settings, "backup.create Roundtrip settings")
        XCTAssertEqual(parsed.entries, expectedEntries, "backup.create Roundtrip entries")

        // Swift liest die Sicherung von Android.
        let fromKotlin = try BackupFormat.parse(kotlinText)
        XCTAssertEqual(fromKotlin, parsed, "backup.create: Kotlin-Text gelesen")
    }

    func testBackupParse() throws {
        let cases = try vectors().field("backup").requiredArray("parse")
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let text = try item.requiredString("text")
            let context = "backup.parse[\(index)] text=\(text.debugDescription)"
            let isError = try item.requiredBool("error")
            if isError {
                let message = try item.requiredString("message")
                XCTAssertThrowsError(try BackupFormat.parse(text), context) { error in
                    XCTAssertEqual((error as? BackupError)?.message, message, context)
                    XCTAssertEqual((error as? LocalizedError)?.errorDescription, message, context)
                }
                continue
            }
            let data: BackupData
            do {
                data = try BackupFormat.parse(text)
            } catch {
                XCTFail("\(context): unerwarteter Fehler \(error)")
                continue
            }

            let createdAt = try item.field("createdAt")
            XCTAssertEqual(data.createdAt?.iso, createdAt.stringValue, "createdAt – \(context)")

            let settings = try item.field("settings")
            if settings.isNull {
                XCTAssertNil(data.settings, "settings – \(context)")
            } else if let parsedSettings = data.settings {
                XCTAssertTrue(
                    BackupFormat.settingsValue(parsedSettings).isSemanticallyEqual(to: settings),
                    "settings – \(context): \(BackupFormat.encodeSettings(parsedSettings)) statt \(settings.serialized())"
                )
            } else {
                XCTFail("settings fehlen – \(context)")
            }

            let expectedEntries = try item.requiredArray("entries")
            let actualEntries = JSONValue.array(data.entries.map { BackupFormat.entryValue($0, includeDate: true) })
            XCTAssertTrue(
                actualEntries.isSemanticallyEqual(to: JSONValue.array(expectedEntries)),
                "entries – \(context): \(actualEntries.serialized()) statt \(JSONValue.array(expectedEntries).serialized())"
            )
        }
    }
}
