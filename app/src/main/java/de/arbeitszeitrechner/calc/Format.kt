package de.arbeitszeitrechner.calc

import java.time.LocalDate
import java.time.LocalTime
import java.time.YearMonth
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** 510 -> "8:30", -90 -> "−1:30" */
fun formatDuration(minutes: Int): String {
    val sign = if (minutes < 0) "−" else ""
    val value = abs(minutes)
    return String.format(Locale.ROOT, "%s%d:%02d", sign, value / 60, value % 60)
}

/** Wie [formatDuration], aber mit "+" bei positiven Werten. */
fun formatBalance(minutes: Int): String =
    if (minutes > 0) "+" + formatDuration(minutes) else formatDuration(minutes)

fun formatTime(time: LocalTime): String =
    String.format(Locale.ROOT, "%02d:%02d", time.hour, time.minute)

/** Akzeptiert "40", "38,5", "38.5" und "38:30". Liefert Minuten oder null. */
fun parseHours(text: String): Int? {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return null
    if (':' in trimmed) {
        val parts = trimmed.split(':')
        if (parts.size != 2) return null
        val hours = parts[0].trim().toIntOrNull() ?: return null
        val minutes = parts[1].trim().toIntOrNull() ?: return null
        if (hours < 0 || minutes !in 0..59) return null
        return hours * 60 + minutes
    }
    val value = trimmed.replace(',', '.').toDoubleOrNull() ?: return null
    if (value < 0 || value.isNaN() || value.isInfinite()) return null
    return (value * 60).roundToInt()
}

/** 480 -> "8", 510 -> "8,5", 505 -> "8:25" */
fun formatHoursInput(minutes: Int): String = when {
    minutes % 60 == 0 -> (minutes / 60).toString()
    minutes % 30 == 0 -> "${minutes / 60},5"
    else -> String.format(Locale.ROOT, "%d:%02d", minutes / 60, minutes % 60)
}

private val DAY_NAMES = listOf("Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag")
private val MONTH_NAMES = listOf(
    "Januar", "Februar", "März", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
)

fun germanDayName(date: LocalDate): String = DAY_NAMES[date.dayOfWeek.value - 1]

/** "September 2026" */
fun germanMonthName(month: YearMonth): String = "${MONTH_NAMES[month.monthValue - 1]} ${month.year}"

/** 615 -> "10,25" (Dezimalstunden, z. B. für die Lohnabrechnung) */
fun formatDecimalHours(minutes: Int): String = String.format(Locale.GERMANY, "%.2f", minutes / 60.0)
