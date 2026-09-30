package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.AppSettings

object BreakCalculator {

    /** Mindestpause in Minuten für eine Anwesenheit von [attendanceMinutes]. */
    fun requiredBreak(attendanceMinutes: Int, settings: AppSettings): Int {
        if (!settings.autoBreak || attendanceMinutes <= 0) return 0
        val rules = settings.breakRules.filter { it.breakMinutes > 0 }
        return if (settings.gradualDeduction) {
            // Jede Regel ist erfüllt, wenn entweder die volle Pause gemacht wurde oder die
            // Arbeitszeit (Anwesenheit - Pause) die Schwelle nicht überschreitet.
            rules.maxOfOrNull { rule ->
                minOf(rule.breakMinutes, (attendanceMinutes - rule.afterMinutes).coerceAtLeast(0))
            } ?: 0
        } else {
            rules.filter { attendanceMinutes > it.afterMinutes }.maxOfOrNull { it.breakMinutes } ?: 0
        }
    }

    /** Tatsächlich abgezogene Pause: die eingetragene Pause, aber mindestens die gesetzliche. */
    fun deductedBreak(attendanceMinutes: Int, manualBreakMinutes: Int, settings: AppSettings): Int {
        val manual = manualBreakMinutes.coerceAtLeast(0)
        return maxOf(manual, requiredBreak(attendanceMinutes, settings))
            .coerceAtMost(attendanceMinutes.coerceAtLeast(0))
    }
}
