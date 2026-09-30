package de.arbeitszeitrechner.ui

import de.arbeitszeitrechner.calc.DayResult
import de.arbeitszeitrechner.calc.WeekSummary
import de.arbeitszeitrechner.calc.formatBalance
import de.arbeitszeitrechner.calc.formatDuration
import de.arbeitszeitrechner.calc.formatHoursInput
import de.arbeitszeitrechner.calc.formatTime
import de.arbeitszeitrechner.model.AppSettings
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.IsoFields

private val DAY_NAMES = listOf("Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag")

val SHORT_DATE: DateTimeFormatter = DateTimeFormatter.ofPattern("dd.MM.")
val LONG_DATE: DateTimeFormatter = DateTimeFormatter.ofPattern("dd.MM.yyyy")

fun dayName(date: LocalDate): String = DAY_NAMES[date.dayOfWeek.value - 1]

fun shortDayName(date: LocalDate): String = dayName(date).take(2)

fun weekNumber(weekStart: LocalDate): Int = weekStart.get(IsoFields.WEEK_OF_WEEK_BASED_YEAR)

fun weekRange(weekStart: LocalDate): String =
    "${SHORT_DATE.format(weekStart)} – ${LONG_DATE.format(weekStart.plusDays(6))}"

/** Kurzbeschreibung der Pausenregeln, z. B. "mehr als 6 h → 30 min, mehr als 9 h → 45 min". */
fun breakRulesText(settings: AppSettings): String =
    settings.breakRules
        .filter { it.breakMinutes > 0 }
        .sortedBy { it.afterMinutes }
        .joinToString(", ") { "mehr als ${formatHoursInput(it.afterMinutes)} h → ${it.breakMinutes} min" }

private fun dayLine(day: DayResult): String? {
    val entry = day.entry
    return when {
        entry.type.isAbsence -> "${entry.type.label} → ${formatDuration(day.creditedMinutes)} h"
        entry.start != null && entry.end != null ->
            "${formatTime(entry.start)}–${formatTime(entry.end)}, Pause ${formatDuration(day.breakMinutes)} → " +
                "${formatDuration(day.creditedMinutes)} h"
        day.running -> "seit ${formatTime(entry.start!!)} (läuft) → ${formatDuration(day.creditedMinutes)} h"
        else -> null
    }
}

/** Text zum Teilen einer Woche (z. B. per Mail oder Messenger). */
fun weekShareText(summary: WeekSummary): String = buildString {
    appendLine("Arbeitszeit KW ${weekNumber(summary.weekStart)} (${weekRange(summary.weekStart)})")
    appendLine()
    summary.days.forEach { day ->
        dayLine(day)?.let { appendLine("${shortDayName(day.entry.date)} ${SHORT_DATE.format(day.entry.date)}: $it") }
    }
    appendLine()
    appendLine("Summe: ${formatDuration(summary.actualMinutes)} h")
    appendLine("Soll: ${formatDuration(summary.targetMinutes)} h")
    appendLine("Saldo: ${formatBalance(summary.balanceMinutes)} h")
    append("Abgezogene Pausen: ${formatDuration(summary.breakMinutes)} h")
}
