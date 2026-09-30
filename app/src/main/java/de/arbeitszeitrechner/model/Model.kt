package de.arbeitszeitrechner.model

import java.time.LocalDate
import java.time.LocalTime

enum class DayType(val label: String) {
    WORK("Arbeit"),
    VACATION("Urlaub"),
    SICK("Krank"),
    HOLIDAY("Feiertag");

    /** Abwesenheitstage werden mit der täglichen Sollzeit gutgeschrieben. */
    val isAbsence: Boolean get() = this != WORK
}

data class DayEntry(
    val date: LocalDate,
    val type: DayType = DayType.WORK,
    val start: LocalTime? = null,
    val end: LocalTime? = null,
    /** Tatsächlich gemachte Pause in Minuten (optional). */
    val manualBreakMinutes: Int = 0,
) {
    val isEmpty: Boolean
        get() = type == DayType.WORK && start == null && end == null && manualBreakMinutes == 0
}

/** Ab mehr als [afterMinutes] Arbeitszeit sind mindestens [breakMinutes] Pause vorgeschrieben. */
data class BreakRule(val afterMinutes: Int, val breakMinutes: Int)

data class AppSettings(
    val weeklyTargetMinutes: Int = 40 * 60,
    val workDaysPerWeek: Int = 5,
    val autoBreak: Boolean = true,
    /**
     * true: Es wird nur so viel Pause abgezogen, dass die Arbeitszeit nicht unter die
     * jeweilige Schwelle fällt (6:15 h Anwesenheit -> 6:00 h Arbeit), wie es § 4 ArbZG entspricht.
     * false: Die volle Pause wird abgezogen, sobald die Anwesenheit die Schwelle überschreitet.
     */
    val gradualDeduction: Boolean = true,
    val breakRules: List<BreakRule> = DEFAULT_BREAK_RULES,
) {
    val dailyTargetMinutes: Int
        get() = weeklyTargetMinutes / workDaysPerWeek.coerceIn(1, 7)

    companion object {
        /** § 4 Arbeitszeitgesetz: > 6 h -> 30 min, > 9 h -> 45 min. */
        val DEFAULT_BREAK_RULES = listOf(BreakRule(6 * 60, 30), BreakRule(9 * 60, 45))
    }
}
