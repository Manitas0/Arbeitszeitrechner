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

/**
 * Text zum Tagesziel, z. B. "20 h voll um 18:45" oder "Tagessoll um 18:45".
 * [weekReached]: Die Wochenstunden sind inklusive der laufenden Zeit bereits erreicht.
 */
fun goalText(goal: TodayGoal, settings: AppSettings, weekReached: Boolean = false): String {
    val week = "${formatHoursInput(settings.weeklyTargetMinutes)} h"
    return when (goal) {
        is TodayGoal.WeekFull -> when {
            !weekReached -> "$week voll um ${formatTime(goal.at)}"
            settings.weeklyHoursAreLimit -> "$week voll – jetzt ausstempeln"
            else -> "$week voll"
        }
        TodayGoal.WeekAlreadyFull ->
            if (settings.weeklyHoursAreLimit) "$week sind schon voll – nicht weiterarbeiten" else "$week sind schon voll"
        is TodayGoal.DailyTarget -> "Tagessoll um ${formatTime(goal.at)}"
    }
}

/**
 * Status von heute, z. B. "Seit 08:00 · 20 h voll um 18:45".
 * [otherDaysMinutes] sind die angerechneten Minuten der übrigen Tage dieser Woche.
 */
fun todayStatusText(today: DayResult, otherDaysMinutes: Int, settings: AppSettings): String {
    val entry = today.entry
    val start = entry.start
    val end = entry.end
    return when {
        entry.type.isAbsence -> "Heute: ${entry.type.label}"
        start != null && end == null -> {
            val goal = WorkCalculator.todayGoal(entry, otherDaysMinutes, settings)
            "Seit ${formatTime(start)}" + goal?.let { " · " + goalText(it, settings) }.orEmpty()
        }
        start != null && end != null ->
            "Heute ${formatTime(start)}–${formatTime(end)} · ${formatDuration(today.creditedMinutes)} h"
        else -> "Heute noch nicht eingestempelt"
    }
}
