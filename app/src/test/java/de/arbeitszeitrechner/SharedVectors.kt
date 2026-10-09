package de.arbeitszeitrechner

import de.arbeitszeitrechner.backup.BackupFormat
import de.arbeitszeitrechner.calc.BreakCalculator
import de.arbeitszeitrechner.calc.ClockAction
import de.arbeitszeitrechner.calc.DayResult
import de.arbeitszeitrechner.calc.MonthExport
import de.arbeitszeitrechner.calc.TodayGoal
import de.arbeitszeitrechner.calc.WorkCalculator
import de.arbeitszeitrechner.calc.applyClockAction
import de.arbeitszeitrechner.calc.formatBalance
import de.arbeitszeitrechner.calc.formatDecimalHours
import de.arbeitszeitrechner.calc.formatDuration
import de.arbeitszeitrechner.calc.formatHoursInput
import de.arbeitszeitrechner.calc.formatTime
import de.arbeitszeitrechner.calc.germanDayName
import de.arbeitszeitrechner.calc.germanMonthName
import de.arbeitszeitrechner.calc.goalText
import de.arbeitszeitrechner.calc.nextClockAction
import de.arbeitszeitrechner.calc.parseHours
import de.arbeitszeitrechner.calc.todayStatusText
import de.arbeitszeitrechner.calc.weekStatusText
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.BreakRule
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import de.arbeitszeitrechner.ui.breakRulesText
import de.arbeitszeitrechner.ui.weekNumber
import de.arbeitszeitrechner.ui.weekRange
import de.arbeitszeitrechner.ui.weekShareText
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.YearMonth


private val SETTINGS = linkedMapOf(
    "werkstudent" to AppSettings(),
    "vollzeit" to AppSettings(weeklyTargetMinutes = 40 * 60, workDaysPerWeek = 5, weeklyHoursAreLimit = false),
    "pauschal" to AppSettings(gradualDeduction = false),
    "ohnePause" to AppSettings(autoBreak = false),
    "eigeneRegeln" to AppSettings(
        weeklyTargetMinutes = 38 * 60 + 30, workDaysPerWeek = 5, weeklyHoursAreLimit = false,
        breakRules = listOf(BreakRule(5 * 60, 20), BreakRule(9 * 60, 0)),
    ),
)

private fun settingsJson(s: AppSettings): JSONObject =
    JSONObject(BackupFormat.create(emptyList(), s, LocalDateTime.of(2026, 1, 1, 0, 0))).getJSONObject("settings")

private fun entryJson(e: DayEntry): JSONObject = BackupFormat.encodeEntry(e).put("date", e.date.toString())

private fun resultJson(r: DayResult) = JSONObject()
    .put("attendanceMinutes", r.attendanceMinutes)
    .put("breakMinutes", r.breakMinutes)
    .put("autoBreakApplied", r.autoBreakApplied)
    .put("creditedMinutes", r.creditedMinutes)
    .put("running", r.running)
    .put("exceedsDailyMax", r.exceedsDailyMax)

private fun t(h: Int, m: Int = 0): LocalTime = LocalTime.of(h, m)
private fun d(y: Int, mo: Int, day: Int): LocalDate = LocalDate.of(y, mo, day)

/**
 * Erzeugt die gemeinsamen Testfälle (shared/test-vectors.json) aus der Kotlin-Implementierung.
 * Die iOS- und die Web-Version prüfen ihre Berechnungen gegen diese Datei.
 */
object SharedVectors {

fun generate(): JSONObject {
    val out = JSONObject()
    out.put("_info", "Automatisch erzeugt aus der Kotlin-Implementierung (Android). Nicht von Hand ändern.")

    val settingsObj = JSONObject()
    SETTINGS.forEach { (name, s) -> settingsObj.put(name, settingsJson(s)) }
    out.put("settings", settingsObj)

    // Pausen
    val breaks = JSONArray()
    for ((name, s) in SETTINGS) {
        for (attendance in (0..720 step 5) + listOf(361, 541, 365, 375, 545, 555, 1)) {
            for (manual in listOf(0, 15, 60)) {
                breaks.put(
                    JSONObject().put("settings", name).put("attendance", attendance).put("manual", manual)
                        .put("required", BreakCalculator.requiredBreak(attendance, s))
                        .put("deducted", BreakCalculator.deductedBreak(attendance, manual, s)),
                )
            }
        }
    }
    out.put("breaks", breaks)

    // Tage
    val monday = d(2026, 9, 28)
    val dayEntries = listOf(
        DayEntry(monday),
        DayEntry(monday, start = t(8), end = t(16, 30)),
        DayEntry(monday, start = t(8), end = t(18, 45)),
        DayEntry(monday, start = t(8), end = t(19)),
        DayEntry(monday, start = t(22), end = t(6)),
        DayEntry(monday, start = t(9), end = t(15, 10)),
        DayEntry(monday, start = t(9), end = t(15, 10), manualBreakMinutes = 45),
        DayEntry(monday, start = t(7, 3), end = t(17, 58), manualBreakMinutes = 10),
        DayEntry(monday, start = t(8)),
        DayEntry(monday, end = t(16)),
        DayEntry(monday, start = t(8), end = t(8)),
        DayEntry(monday, type = DayType.VACATION),
        DayEntry(monday, type = DayType.SICK),
        DayEntry(monday, type = DayType.HOLIDAY),
    )
    val nows = listOf<LocalDateTime?>(null, LocalDateTime.of(monday, t(15)), LocalDateTime.of(monday, t(7)),
        LocalDateTime.of(monday.plusDays(1), t(10)))
    val days = JSONArray()
    for ((name, s) in SETTINGS) for (e in dayEntries) for (now in nows) {
        val o = JSONObject().put("settings", name).put("entry", entryJson(e))
        now?.let { o.put("now", it.toString()) }
        o.put("result", resultJson(WorkCalculator.evaluate(e, s, now)))
        days.put(o)
    }
    out.put("days", days)

    // Wochen
    val weekCases = listOf(
        emptyMap(),
        mapOf(
            monday to DayEntry(monday, start = t(8), end = t(16, 30)),
            monday.plusDays(1) to DayEntry(monday.plusDays(1), start = t(7), end = t(17)),
            monday.plusDays(2) to DayEntry(monday.plusDays(2), type = DayType.SICK),
            monday.plusDays(3) to DayEntry(monday.plusDays(3), start = t(9), end = t(15, 10)),
        ),
        mapOf(
            monday to DayEntry(monday, start = t(8), end = t(18, 45)),
            monday.plusDays(3) to DayEntry(monday.plusDays(3), start = t(9), end = t(19, 45)),
        ),
        mapOf(
            monday to DayEntry(monday, start = t(8), end = t(19, 15)),
            monday.plusDays(1) to DayEntry(monday.plusDays(1), start = t(8)),
            monday.plusDays(6) to DayEntry(monday.plusDays(6), start = t(10), end = t(12, 30), manualBreakMinutes = 20),
        ),
    )
    val weeks = JSONArray()
    for ((name, s) in SETTINGS) for ((index, entries) in weekCases.withIndex()) for (now in listOf(null, LocalDateTime.of(monday.plusDays(1), t(15)))) {
        val summary = WorkCalculator.summarizeWeek(monday, entries, s, now)
        val o = JSONObject().put("settings", name).put("case", index).put("weekStart", monday.toString())
            .put("entries", JSONArray(entries.values.map(::entryJson)))
        now?.let { o.put("now", it.toString()) }
        o.put("days", JSONArray(summary.days.map(::resultJson)))
        o.put("actualMinutes", summary.actualMinutes).put("targetMinutes", summary.targetMinutes)
            .put("breakMinutes", summary.breakMinutes).put("balanceMinutes", summary.balanceMinutes)
            .put("minutesExcludingTuesday", summary.minutesExcluding(monday.plusDays(1)))
            .put("weekStatusLimit", weekStatusText(summary, true))
            .put("weekStatusNoLimit", weekStatusText(summary, false))
            .put("shareTextLimit", weekShareText(summary, true))
            .put("shareTextNoLimit", weekShareText(summary, false))
        weeks.put(o)
    }
    out.put("weeks", weeks)

    // Tagesziel (eingestempelt) und Statustexte
    val goals = JSONArray()
    val goalEntries = listOf(
        DayEntry(monday, start = t(8)),
        DayEntry(monday, start = t(8), manualBreakMinutes = 60),
        DayEntry(monday, start = t(13, 17)),
        DayEntry(monday, start = t(20)),
        DayEntry(monday),
        DayEntry(monday, start = t(8), end = t(18, 45)),
        DayEntry(monday, type = DayType.HOLIDAY),
    )
    for ((name, s) in SETTINGS) for (e in goalEntries) for (other in listOf(0, 300, 570, 600, 630, 900, 1140, 1200, 1500, 1800, 1830, 2100, 2400)) {
        val goal = WorkCalculator.todayGoal(e, other, s)
        val g = when (goal) {
            null -> JSONObject.NULL
            is TodayGoal.WeekFull -> JSONObject().put("kind", "weekFull").put("at", formatTime(goal.at))
            TodayGoal.WeekAlreadyFull -> JSONObject().put("kind", "weekAlreadyFull")
            is TodayGoal.DailyTarget -> JSONObject().put("kind", "dailyTarget").put("at", formatTime(goal.at))
        }
        val o = JSONObject().put("settings", name).put("entry", entryJson(e)).put("otherDaysMinutes", other).put("goal", g)
        if (goal != null) {
            o.put("text", goalText(goal, s)).put("textReached", goalText(goal, s, weekReached = true))
        }
        o.put("todayStatus", todayStatusText(WorkCalculator.evaluate(e, s), other, s))
        goals.put(o)
    }
    out.put("goals", goals)

    // Endzeit für ein Ziel
    val endTimes = JSONArray()
    for ((name, s) in SETTINGS) for (start in listOf(t(8), t(22, 30), t(0))) for (manual in listOf(0, 50)) for (target in listOf(0, 300, 360, 361, 480, 540, 541, 570, 600)) {
        endTimes.put(JSONObject().put("settings", name).put("start", formatTime(start)).put("manual", manual)
            .put("target", target).put("end", formatTime(WorkCalculator.endTimeForTarget(start, manual, target, s))))
    }
    out.put("endTimes", endTimes)

    // Formatierung
    val format = JSONObject()
    val minutes = listOf(0, 1, 5, 59, 60, 61, 90, 465, 468, 480, 505, 510, 555, 600, 615, 1200, 1230, 2310, 2400, 10080, -1, -15, -90, -600)
    format.put("duration", JSONArray(minutes.map { JSONArray().put(it).put(formatDuration(it)) }))
    format.put("balance", JSONArray(minutes.map { JSONArray().put(it).put(formatBalance(it)) }))
    format.put("hoursInput", JSONArray(minutes.filter { it >= 0 }.map { JSONArray().put(it).put(formatHoursInput(it)) }))
    format.put("decimalHours", JSONArray(minutes.map { JSONArray().put(it).put(formatDecimalHours(it)) }))
    val parseInputs = listOf("40", "38,5", "38.5", "38:30", " 20 ", "0", "7:05", "8:75", "abc", "", "  ", "-5", "1:2:3", "12,25", "12.333", ":30", "8:", "١٢", "1e2", "0,5")
    format.put("parseHours", JSONArray(parseInputs.map { JSONArray().put(it).put(parseHours(it) ?: JSONObject.NULL) }))
    format.put("time", JSONArray(listOf(t(0), t(8), t(9, 5), t(23, 59)).map { JSONArray().put(it.toString()).put(formatTime(it)) }))
    out.put("format", format)

    // Datum
    val dates = JSONArray()
    var date = d(2024, 12, 28)
    while (date <= d(2025, 1, 8)) { dates.put(dateJson(date)); date = date.plusDays(1) }
    for (x in listOf(d(2026, 9, 28), d(2026, 10, 4), d(2026, 2, 28), d(2028, 2, 29), d(2026, 12, 31), d(2027, 1, 1), d(2020, 12, 31), d(2021, 1, 3))) dates.put(dateJson(x))
    out.put("dates", dates)

    // Pausenregel-Texte
    out.put("breakRulesText", JSONArray(SETTINGS.map { (name, s) -> JSONArray().put(name).put(breakRulesText(s)) }))

    // Stempeln
    val clock = JSONArray()
    for (e in dayEntries) {
        val next = nextClockAction(e)
        val o = JSONObject().put("entry", entryJson(e)).put("next", next?.name ?: JSONObject.NULL)
        if (next != null) o.put("applied", entryJson(applyClockAction(e, next, t(12, 34))))
        clock.put(o)
    }
    clock.put(JSONObject().put("entry", entryJson(DayEntry(monday, type = DayType.WORK, start = t(9), manualBreakMinutes = 15)))
        .put("next", ClockAction.CLOCK_OUT.name)
        .put("applied", entryJson(applyClockAction(DayEntry(monday, start = t(9), manualBreakMinutes = 15), ClockAction.CLOCK_OUT, t(12, 34)))))
    out.put("clock", clock)

    // Monatsexport (CSV)
    val september = YearMonth.of(2026, 9)
    val csvEntries = mapOf(
        d(2026, 9, 1) to DayEntry(d(2026, 9, 1), start = t(8), end = t(18, 45)),
        d(2026, 9, 3) to DayEntry(d(2026, 9, 3), start = t(9), end = t(14, 30)),
        d(2026, 9, 8) to DayEntry(d(2026, 9, 8), type = DayType.VACATION),
        d(2026, 9, 10) to DayEntry(d(2026, 9, 10), start = t(22), end = t(6, 15), manualBreakMinutes = 40),
        d(2026, 9, 15) to DayEntry(d(2026, 9, 15), start = t(8)),
        d(2026, 9, 29) to DayEntry(d(2026, 9, 29), type = DayType.HOLIDAY),
        d(2026, 10, 1) to DayEntry(d(2026, 10, 1), start = t(8), end = t(12)),
    )
    val csv = JSONArray()
    for ((name, s) in SETTINGS) for (month in listOf(september, YearMonth.of(2026, 10), YearMonth.of(2026, 2))) {
        val summary = MonthExport.summary(month, csvEntries, s)
        csv.put(JSONObject().put("settings", name).put("month", month.toString())
            .put("entries", JSONArray(csvEntries.values.map(::entryJson)))
            .put("fileName", MonthExport.fileName(month))
            .put("monthName", germanMonthName(month))
            .put("csv", MonthExport.csv(month, csvEntries, s))
            .put("summary", JSONObject().put("workedMinutes", summary.workedMinutes).put("absenceMinutes", summary.absenceMinutes)
                .put("workDays", summary.workDays).put("absenceDays", summary.absenceDays).put("totalMinutes", summary.totalMinutes)))
    }
    out.put("csv", csv)

    // Sicherung
    val backup = JSONObject()
    val sampleEntries = csvEntries.values.toList() + DayEntry(d(2026, 9, 20))
    val createdAt = LocalDateTime.of(2026, 9, 30, 14, 55, 12)
    backup.put("create", JSONObject()
        .put("entries", JSONArray(sampleEntries.map(::entryJson)))
        .put("settings", "eigeneRegeln")
        .put("createdAt", createdAt.toString())
        .put("text", BackupFormat.create(sampleEntries, SETTINGS.getValue("eigeneRegeln"), createdAt)))
    val parseCases = listOf(
        BackupFormat.create(sampleEntries, SETTINGS.getValue("werkstudent"), createdAt),
        Char(0xFEFF) + """{"app":"Arbeitszeitrechner","entries":[{"date":"2026-09-28","start":"09:00"}]}""",
        """{"app":"Arbeitszeitrechner","version":1,"createdAt":"2026-09-30T08:00:00","settings":{"weeklyTargetMinutes":99999,"workDaysPerWeek":9,"breakRules":[{"after":300}]},"entries":[{"date":"kaputt"},{"date":"2026-09-29","type":"UNBEKANNT","start":"07:30","end":"16:00","break":-5},{"date":"2026-09-30","type":"SICK"}]}""",
        """{"app":"Arbeitszeitrechner","createdAt":"gestern","entries":[]}""",
        """{"foo":1}""",
        "kein JSON",
        "",
    )
    backup.put("parse", JSONArray(parseCases.map { text ->
        val o = JSONObject().put("text", text)
        try {
            val data = BackupFormat.parse(text)
            o.put("error", false)
                .put("createdAt", data.createdAt?.toString() ?: JSONObject.NULL)
                .put("settings", data.settings?.let(::settingsJson) ?: JSONObject.NULL)
                .put("entries", JSONArray(data.entries.map(::entryJson)))
        } catch (e: IllegalArgumentException) {
            o.put("error", true).put("message", e.message)
        }
        o
    }))
    out.put("backup", backup)

    return out
}

fun dateJson(date: LocalDate) = JSONObject()
    .put("date", date.toString())
    .put("weekStart", WorkCalculator.weekStartOf(date).toString())
    .put("isoWeek", weekNumber(date))
    .put("weekRange", weekRange(WorkCalculator.weekStartOf(date)))
    .put("dayName", germanDayName(date))
    .put("monthName", germanMonthName(YearMonth.from(date)))
}
