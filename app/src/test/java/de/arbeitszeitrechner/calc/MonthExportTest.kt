package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime
import java.time.YearMonth

class MonthExportTest {

    private val settings = AppSettings()
    private val september = YearMonth.of(2026, 9)

    private fun d(day: Int) = LocalDate.of(2026, 9, day)
    private fun t(hour: Int, minute: Int = 0) = LocalTime.of(hour, minute)

    private val entries = mapOf(
        d(1) to DayEntry(d(1), start = t(8), end = t(18, 45)),
        d(3) to DayEntry(d(3), start = t(9), end = t(14, 30)),
        d(8) to DayEntry(d(8), type = DayType.VACATION),
        LocalDate.of(2026, 10, 1) to DayEntry(LocalDate.of(2026, 10, 1), start = t(8), end = t(12)),
    )

    @Test
    fun csvTimesheet() {
        val expected = listOf(
            "Stundenzettel September 2026",
            "",
            "KW;Datum;Wochentag;Art;Beginn;Ende;Pause (Min.);Stunden (h:mm);Stunden (dezimal)",
            "36;01.09.2026;Dienstag;Arbeit;08:00;18:45;45;10:00;10,00",
            "36;03.09.2026;Donnerstag;Arbeit;09:00;14:30;0;5:30;5,50",
            "37;08.09.2026;Dienstag;Urlaub;;;;10:00;10,00",
            "",
            "Summe gearbeitet;;;;;;;15:30;15,50",
            "Gutschrift Urlaub/Krank/Feiertag;;;;;;;10:00;10,00",
            "Gesamt;;;;;;;25:30;25,50",
        ).joinToString("\r\n", postfix = "\r\n")
        assertEquals(Char(0xFEFF) + expected, MonthExport.csv(september, entries, settings))
    }

    @Test
    fun summary() {
        val summary = MonthExport.summary(september, entries, settings)
        assertEquals(930, summary.workedMinutes)
        assertEquals(600, summary.absenceMinutes)
        assertEquals(2, summary.workDays)
        assertEquals(1, summary.absenceDays)
        assertEquals(1530, summary.totalMinutes)
    }

    @Test
    fun fileName() {
        assertEquals("Arbeitszeit-2026-09.csv", MonthExport.fileName(september))
    }
}
