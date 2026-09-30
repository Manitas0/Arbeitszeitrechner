package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime

class ClockAndStatusTest {

    private val monday = LocalDate.of(2026, 9, 28)
    private val settings = AppSettings()

    private fun t(hour: Int, minute: Int = 0) = LocalTime.of(hour, minute)

    @Test
    fun nextActionFollowsTheDay() {
        assertEquals(ClockAction.CLOCK_IN, nextClockAction(DayEntry(monday)))
        assertEquals(ClockAction.CLOCK_OUT, nextClockAction(DayEntry(monday, start = t(8))))
        assertNull(nextClockAction(DayEntry(monday, start = t(8), end = t(18, 45))))
        assertNull(nextClockAction(DayEntry(monday, type = DayType.VACATION)))
    }

    @Test
    fun clockInAndOut() {
        val clockedIn = applyClockAction(DayEntry(monday, manualBreakMinutes = 15), ClockAction.CLOCK_IN, t(8, 3))
        assertEquals(t(8, 3), clockedIn.start)
        assertNull(clockedIn.end)
        assertEquals(15, clockedIn.manualBreakMinutes)

        val clockedOut = applyClockAction(clockedIn, ClockAction.CLOCK_OUT, t(18, 50))
        assertEquals(t(8, 3), clockedOut.start)
        assertEquals(t(18, 50), clockedOut.end)
    }

    @Test
    fun weekStatus() {
        fun summary(actual: Int) = WeekSummary(monday, emptyList(), actual, 1200, 0)
        assertEquals("Noch 7:30 h bis zur Grenze", weekStatusText(summary(750), isLimit = true))
        assertEquals("Noch 0:00 h bis zur Grenze", weekStatusText(summary(1200), isLimit = true))
        assertEquals("Grenze um 1:15 h überschritten", weekStatusText(summary(1275), isLimit = true))
        assertEquals("Noch 7:30 h offen", weekStatusText(summary(750), isLimit = false))
        assertEquals("+1:15 h Überstunden", weekStatusText(summary(1275), isLimit = false))
    }

    @Test
    fun todayStatus() {
        fun status(entry: DayEntry, otherDays: Int = 0) =
            todayStatusText(WorkCalculator.evaluate(entry, settings), otherDays, settings)
        assertEquals("Heute noch nicht eingestempelt", status(DayEntry(monday)))
        assertEquals("Seit 08:00 · Tagessoll um 18:45", status(DayEntry(monday, start = t(8))))
        assertEquals("Seit 08:00 · 20 h voll um 18:45", status(DayEntry(monday, start = t(8)), otherDays = 600))
        assertEquals("Heute 08:00–18:45 · 10:00 h", status(DayEntry(monday, start = t(8), end = t(18, 45))))
        assertEquals("Heute: Krank", status(DayEntry(monday, type = DayType.SICK)))
    }

    @Test
    fun lastDayGoalUsesRemainingWeekHours() {
        val running = DayEntry(monday, start = t(8))
        // Erster Tag: Die Woche wird heute nicht voll -> Tagessoll (10 h + 45 min Pause).
        assertEquals(TodayGoal.DailyTarget(t(18, 45)), WorkCalculator.todayGoal(running, 0, settings))
        // Letzter Tag nach genau 10 h: noch 10 h offen.
        assertEquals(TodayGoal.WeekFull(t(18, 45)), WorkCalculator.todayGoal(running, 600, settings))
        // Am ersten Tag 10:30 h gearbeitet: nur noch 9:30 h, sonst wird die 20-h-Grenze überschritten.
        assertEquals(TodayGoal.WeekFull(t(18, 15)), WorkCalculator.todayGoal(running, 630, settings))
        // Nur noch 5 h offen: keine Pause nötig.
        assertEquals(TodayGoal.WeekFull(t(13)), WorkCalculator.todayGoal(running, 900, settings))
        // Am ersten Tag nur 9:30 h: 10:30 h wären über der Tageshöchstgrenze -> Tagessoll.
        assertEquals(TodayGoal.DailyTarget(t(18, 45)), WorkCalculator.todayGoal(running, 570, settings))
        // Schon voll.
        assertEquals(TodayGoal.WeekAlreadyFull, WorkCalculator.todayGoal(running, 1200, settings))
        assertNull(WorkCalculator.todayGoal(DayEntry(monday), 600, settings))
    }

    @Test
    fun goalTexts() {
        assertEquals("20 h voll um 18:15", goalText(TodayGoal.WeekFull(t(18, 15)), settings))
        assertEquals(
            "20 h voll – jetzt ausstempeln",
            goalText(TodayGoal.WeekFull(t(18, 15)), settings, weekReached = true),
        )
        assertEquals("20 h sind schon voll – nicht weiterarbeiten", goalText(TodayGoal.WeekAlreadyFull, settings))
        val fullTime = AppSettings(weeklyTargetMinutes = 38 * 60 + 30, workDaysPerWeek = 5, weeklyHoursAreLimit = false)
        assertEquals("38,5 h voll um 15:00", goalText(TodayGoal.WeekFull(t(15)), fullTime))
        assertEquals("Tagessoll um 16:30", goalText(TodayGoal.DailyTarget(t(16, 30)), fullTime))
    }

    @Test
    fun minutesOfOtherDays() {
        val entries = mapOf(
            monday to DayEntry(monday, start = t(8), end = t(18, 45)),
            monday.plusDays(1) to DayEntry(monday.plusDays(1), start = t(8)),
        )
        val summary = WorkCalculator.summarizeWeek(monday, entries, settings)
        assertEquals(600, summary.minutesExcluding(monday.plusDays(1)))
        assertEquals(0, summary.minutesExcluding(monday))
    }
}
