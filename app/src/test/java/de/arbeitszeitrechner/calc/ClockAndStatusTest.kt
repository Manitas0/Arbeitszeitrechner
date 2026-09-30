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
        fun status(entry: DayEntry) = todayStatusText(WorkCalculator.evaluate(entry, settings), settings)
        assertEquals("Heute noch nicht eingestempelt", status(DayEntry(monday)))
        assertEquals("Seit 08:00 · Tagessoll um 18:45", status(DayEntry(monday, start = t(8))))
        assertEquals("Heute 08:00–18:45 · 10:00 h", status(DayEntry(monday, start = t(8), end = t(18, 45))))
        assertEquals("Heute: Krank", status(DayEntry(monday, type = DayType.SICK)))
    }
}
