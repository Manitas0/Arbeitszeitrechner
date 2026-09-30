package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

class WorkCalculatorTest {

    private val settings = AppSettings()
    private val monday = LocalDate.of(2026, 9, 28)

    private fun t(hour: Int, minute: Int = 0) = LocalTime.of(hour, minute)

    @Test
    fun weekStartIsMonday() {
        assertEquals(monday, WorkCalculator.weekStartOf(LocalDate.of(2026, 10, 4)))
        assertEquals(monday, WorkCalculator.weekStartOf(LocalDate.of(2026, 9, 30)))
        assertEquals(monday, WorkCalculator.weekStartOf(monday))
    }

    @Test
    fun regularDay() {
        val result = WorkCalculator.evaluate(DayEntry(monday, start = t(8), end = t(16, 30)), settings)
        assertEquals(510, result.attendanceMinutes)
        assertEquals(30, result.breakMinutes)
        assertTrue(result.autoBreakApplied)
        assertEquals(480, result.creditedMinutes)
    }

    @Test
    fun overnightShift() {
        val result = WorkCalculator.evaluate(DayEntry(monday, start = t(22), end = t(6)), settings)
        assertEquals(480, result.attendanceMinutes)
        assertEquals(450, result.creditedMinutes)
    }

    @Test
    fun incompleteDayCountsNothing() {
        val result = WorkCalculator.evaluate(DayEntry(monday, start = t(8)), settings)
        assertEquals(0, result.creditedMinutes)
        assertFalse(result.running)
    }

    @Test
    fun runningDayUsesCurrentTime() {
        val now = LocalDateTime.of(monday, t(15))
        val result = WorkCalculator.evaluate(DayEntry(monday, start = t(8)), settings, now)
        assertTrue(result.running)
        assertEquals(420, result.attendanceMinutes)
        assertEquals(390, result.creditedMinutes)
    }

    @Test
    fun absenceIsCreditedWithDailyTarget() {
        val result = WorkCalculator.evaluate(DayEntry(monday, type = DayType.VACATION), settings)
        assertEquals(480, result.creditedMinutes)
        assertEquals(0, result.breakMinutes)
    }

    @Test
    fun weekSummary() {
        val entries = mapOf(
            monday to DayEntry(monday, start = t(8), end = t(16, 30)),           // 8:00
            monday.plusDays(1) to DayEntry(monday.plusDays(1), start = t(7), end = t(17)), // 10:00 - 0:45 = 9:15
            monday.plusDays(2) to DayEntry(monday.plusDays(2), type = DayType.SICK),       // 8:00
            monday.plusDays(3) to DayEntry(monday.plusDays(3), start = t(9), end = t(15, 10)), // 6:10 - 0:10 = 6:00
        )
        val summary = WorkCalculator.summarizeWeek(monday, entries, settings)
        assertEquals(7, summary.days.size)
        assertEquals(8 * 60 + 555 + 8 * 60 + 360, summary.actualMinutes)
        assertEquals(40 * 60, summary.targetMinutes)
        assertEquals(30 + 45 + 10, summary.breakMinutes)
        assertEquals(summary.actualMinutes - 2400, summary.balanceMinutes)
    }

    @Test
    fun endTimeForTargetIncludesBreak() {
        assertEquals(t(16, 30), WorkCalculator.endTimeForTarget(t(8), 0, 480, settings))
        assertEquals(t(17), WorkCalculator.endTimeForTarget(t(8), 60, 480, settings))
        assertEquals(t(14), WorkCalculator.endTimeForTarget(t(8), 0, 360, settings))
    }

    @Test
    fun parsingAndFormatting() {
        assertEquals(2400, parseHours("40"))
        assertEquals(2310, parseHours("38,5"))
        assertEquals(2310, parseHours("38.5"))
        assertEquals(2310, parseHours("38:30"))
        assertNull(parseHours("abc"))
        assertNull(parseHours("8:75"))
        assertEquals("8:30", formatDuration(510))
        assertEquals("−1:30", formatDuration(-90))
        assertEquals("+0:15", formatBalance(15))
        assertEquals("0:00", formatBalance(0))
        assertEquals("38,5", formatHoursInput(2310))
        assertEquals("40", formatHoursInput(2400))
        assertEquals("7:48", formatHoursInput(468))
    }
}
