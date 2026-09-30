package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.AppSettings

/** Kurzer Wochenstatus, z. B. "Noch 7:30 h bis zur Grenze". */
fun weekStatusText(summary: WeekSummary, isLimit: Boolean): String {
    val balance = summary.balanceMinutes
    return when {
        isLimit && balance > 0 -> "Grenze um ${formatDuration(balance)} h überschritten"
        isLimit -> "Noch ${formatDuration(-balance)} h bis zur Grenze"
        balance < 0 -> "Noch ${formatDuration(-balance)} h offen"
        else -> "+${formatDuration(balance)} h Überstunden"
    }
}

/** Status von heute, z. B. "Seit 08:00 · Tagessoll um 18:45". */
fun todayStatusText(today: DayResult, settings: AppSettings): String {
    val entry = today.entry
    val start = entry.start
    val end = entry.end
    return when {
        entry.type.isAbsence -> "Heute: ${entry.type.label}"
        start != null && end == null -> {
            val target = WorkCalculator.endTimeForTarget(
                start, entry.manualBreakMinutes, settings.dailyTargetMinutes, settings,
            )
            "Seit ${formatTime(start)} · Tagessoll um ${formatTime(target)}"
        }
        start != null && end != null ->
            "Heute ${formatTime(start)}–${formatTime(end)} · ${formatDuration(today.creditedMinutes)} h"
        else -> "Heute noch nicht eingestempelt"
    }
}
