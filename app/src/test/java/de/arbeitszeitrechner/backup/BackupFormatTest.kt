package de.arbeitszeitrechner.backup

import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.BreakRule
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

class BackupFormatTest {

    private val monday = LocalDate.of(2026, 9, 28)

    @Test
    fun roundTrip() {
        val entries = listOf(
            DayEntry(monday, start = LocalTime.of(8, 0), end = LocalTime.of(18, 45), manualBreakMinutes = 50),
            DayEntry(monday.plusDays(1), type = DayType.VACATION),
            DayEntry(monday.plusDays(3), start = LocalTime.of(22, 15)),
        )
        val settings = AppSettings(
            weeklyTargetMinutes = 38 * 60 + 30,
            workDaysPerWeek = 5,
            weeklyHoursAreLimit = false,
            gradualDeduction = false,
            breakRules = listOf(BreakRule(5 * 60, 20), BreakRule(10 * 60, 60)),
        )
        val createdAt = LocalDateTime.of(2026, 9, 30, 14, 55, 12)

        val data = BackupFormat.parse(BackupFormat.create(entries, settings, createdAt))

        assertEquals(entries, data.entries)
        assertEquals(settings, data.settings)
        assertEquals(createdAt, data.createdAt)
    }

    @Test
    fun emptyEntriesAreSkipped() {
        val text = BackupFormat.create(listOf(DayEntry(monday)), AppSettings(), LocalDateTime.now())
        assertEquals(emptyList<DayEntry>(), BackupFormat.parse(text).entries)
    }

    @Test
    fun toleratesByteOrderMarkAndMissingFields() {
        val text = Char(0xFEFF) + """{"app":"Arbeitszeitrechner","entries":[{"date":"2026-09-28","start":"09:00"}]}"""
        val data = BackupFormat.parse(text)
        assertEquals(listOf(DayEntry(monday, start = LocalTime.of(9, 0))), data.entries)
        assertNull(data.settings)
        assertNull(data.createdAt)
    }

    @Test
    fun rejectsForeignFiles() {
        assertThrows(IllegalArgumentException::class.java) { BackupFormat.parse("""{"foo":1}""") }
        assertThrows(IllegalArgumentException::class.java) { BackupFormat.parse("kein JSON") }
    }
}
