package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.IsoFields
import java.util.Locale

/** Stundenzettel für einen Monat als CSV (für Excel, Numbers, Google Tabellen). */
object MonthExport {

    data class Summary(
        val workedMinutes: Int,
        val absenceMinutes: Int,
        val workDays: Int,
        val absenceDays: Int,
    ) {
        val totalMinutes: Int get() = workedMinutes + absenceMinutes
    }

    /** Byte-Order-Mark, damit Excel die Datei als UTF-8 (Umlaute) erkennt. */
    private val BOM = Char(0xFEFF).toString()
    private const val SEPARATOR = ";"
    private const val LINE_END = "\r\n"

    fun fileName(month: YearMonth): String =
        String.format(Locale.ROOT, "Arbeitszeit-%04d-%02d.csv", month.year, month.monthValue)

    private fun daysWithEntries(month: YearMonth, entries: Map<LocalDate, DayEntry>): List<DayEntry> =
        (1..month.lengthOfMonth())
            .mapNotNull { day -> entries[month.atDay(day)] }
            .filterNot { it.isEmpty }

    fun summary(month: YearMonth, entries: Map<LocalDate, DayEntry>, settings: AppSettings): Summary {
        val results = daysWithEntries(month, entries).map { WorkCalculator.evaluate(it, settings) }
        val (absences, work) = results.partition { it.entry.type.isAbsence }
        return Summary(
            workedMinutes = work.sumOf { it.creditedMinutes },
            absenceMinutes = absences.sumOf { it.creditedMinutes },
            workDays = work.count { it.creditedMinutes > 0 },
            absenceDays = absences.size,
        )
    }

    fun csv(month: YearMonth, entries: Map<LocalDate, DayEntry>, settings: AppSettings): String {
        val lines = mutableListOf<List<String>>()
        lines += listOf("Stundenzettel ${germanMonthName(month)}")
        lines += emptyList<String>()
        lines += listOf(
            "KW", "Datum", "Wochentag", "Art", "Beginn", "Ende", "Pause (Min.)",
            "Stunden (h:mm)", "Stunden (dezimal)",
        )
        daysWithEntries(month, entries).forEach { entry ->
            val result = WorkCalculator.evaluate(entry, settings)
            val isWork = !entry.type.isAbsence
            lines += listOf(
                entry.date.get(IsoFields.WEEK_OF_WEEK_BASED_YEAR).toString(),
                String.format(Locale.ROOT, "%02d.%02d.%04d", entry.date.dayOfMonth, entry.date.monthValue, entry.date.year),
                germanDayName(entry.date),
                entry.type.label,
                if (isWork) entry.start?.let(::formatTime).orEmpty() else "",
                if (isWork) entry.end?.let(::formatTime).orEmpty() else "",
                if (isWork) result.breakMinutes.toString() else "",
                formatDuration(result.creditedMinutes),
                formatDecimalHours(result.creditedMinutes),
            )
        }
        val summary = summary(month, entries, settings)
        lines += emptyList<String>()
        lines += sumLine("Summe gearbeitet", summary.workedMinutes)
        if (summary.absenceMinutes > 0) {
            lines += sumLine("Gutschrift Urlaub/Krank/Feiertag", summary.absenceMinutes)
            lines += sumLine("Gesamt", summary.totalMinutes)
        }
        return BOM + lines.joinToString(LINE_END) { it.joinToString(SEPARATOR) } + LINE_END
    }

    private fun sumLine(label: String, minutes: Int) =
        listOf(label, "", "", "", "", "", "", formatDuration(minutes), formatDecimalHours(minutes))
}
