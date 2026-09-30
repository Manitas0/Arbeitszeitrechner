package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import java.time.DayOfWeek
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

data class DayResult(
    val entry: DayEntry,
    /** Zeit zwischen Beginn und Ende (bzw. jetzt, wenn der Tag noch läuft). */
    val attendanceMinutes: Int = 0,
    val breakMinutes: Int = 0,
    /** true, wenn mehr Pause abgezogen wurde als eingetragen. */
    val autoBreakApplied: Boolean = false,
    /** Angerechnete Minuten: Netto-Arbeitszeit oder Gutschrift bei Abwesenheit. */
    val creditedMinutes: Int = 0,
    /** Beginn gesetzt, Ende noch offen und der Tag ist heute. */
    val running: Boolean = false,
) {
    /** Mehr Arbeitszeit als die gesetzliche Tageshöchstgrenze (§ 3 ArbZG). */
    val exceedsDailyMax: Boolean
        get() = !entry.type.isAbsence && creditedMinutes > WorkCalculator.MAX_DAILY_WORK_MINUTES
}

data class WeekSummary(
    val weekStart: LocalDate,
    val days: List<DayResult>,
    val actualMinutes: Int,
    val targetMinutes: Int,
    val breakMinutes: Int,
) {
    val balanceMinutes: Int get() = actualMinutes - targetMinutes

    /** Angerechnete Minuten aller anderen Tage der Woche (ohne [date]). */
    fun minutesExcluding(date: LocalDate): Int =
        days.filter { it.entry.date != date }.sumOf { it.creditedMinutes }
}

/** Ziel für einen Arbeitstag, an dem gerade eingestempelt ist. */
sealed interface TodayGoal {
    /** Die Wochenstunden sind heute um [at] voll. */
    data class WeekFull(val at: LocalTime) : TodayGoal

    /** Die Wochenstunden sind schon durch die anderen Tage voll. */
    data object WeekAlreadyFull : TodayGoal

    /** Die Woche wird heute nicht voll (höchstens 10 h pro Tag); um [at] ist das Tagessoll erreicht. */
    data class DailyTarget(val at: LocalTime) : TodayGoal
}

object WorkCalculator {

    /** § 3 ArbZG: höchstens 10 Stunden Arbeitszeit pro Tag. */
    const val MAX_DAILY_WORK_MINUTES = 10 * 60

    fun weekStartOf(date: LocalDate): LocalDate =
        date.minusDays((date.dayOfWeek.value - DayOfWeek.MONDAY.value).toLong())

    /** Minuten von [start] bis [end]; liegt das Ende vor dem Beginn, geht die Schicht über Mitternacht. */
    fun attendanceMinutes(start: LocalTime, end: LocalTime): Int {
        val minutes = Duration.between(start, end).toMinutes().toInt()
        return if (minutes < 0) minutes + 24 * 60 else minutes
    }

    fun evaluate(entry: DayEntry, settings: AppSettings, now: LocalDateTime? = null): DayResult {
        if (entry.type.isAbsence) {
            return DayResult(entry, creditedMinutes = settings.dailyTargetMinutes)
        }
        val start = entry.start ?: return DayResult(entry)
        val running = entry.end == null && now != null && now.toLocalDate() == entry.date
        val end = entry.end ?: if (running) now!!.toLocalTime() else return DayResult(entry)
        val attendance = if (running) {
            Duration.between(start, end).toMinutes().toInt().coerceAtLeast(0)
        } else {
            attendanceMinutes(start, end)
        }
        val breakMinutes = BreakCalculator.deductedBreak(attendance, entry.manualBreakMinutes, settings)
        return DayResult(
            entry = entry,
            attendanceMinutes = attendance,
            breakMinutes = breakMinutes,
            autoBreakApplied = breakMinutes > entry.manualBreakMinutes,
            creditedMinutes = attendance - breakMinutes,
            running = running,
        )
    }

    fun summarizeWeek(
        weekStart: LocalDate,
        entries: Map<LocalDate, DayEntry>,
        settings: AppSettings,
        now: LocalDateTime? = null,
    ): WeekSummary {
        val days = (0L until 7L).map { offset ->
            val date = weekStart.plusDays(offset)
            evaluate(entries[date] ?: DayEntry(date), settings, now)
        }
        return WeekSummary(
            weekStart = weekStart,
            days = days,
            actualMinutes = days.sumOf { it.creditedMinutes },
            targetMinutes = settings.weeklyTargetMinutes,
            breakMinutes = days.sumOf { it.breakMinutes },
        )
    }

    /**
     * Uhrzeit, zu der bei Beginn um [start] die Sollzeit [targetMinutes] netto erreicht ist,
     * inklusive der automatisch abgezogenen Pause.
     */
    /**
     * Bis wann heute gearbeitet werden muss (bzw. darf): Lassen sich die restlichen Wochenstunden heute
     * schaffen, zählt der Zeitpunkt, an dem die Woche voll ist – sonst das Tagessoll.
     * [otherDaysMinutes] sind die angerechneten Minuten der übrigen Tage dieser Woche.
     */
    fun todayGoal(entry: DayEntry, otherDaysMinutes: Int, settings: AppSettings): TodayGoal? {
        val start = entry.start ?: return null
        val remaining = settings.weeklyTargetMinutes - otherDaysMinutes
        return when {
            remaining <= 0 -> TodayGoal.WeekAlreadyFull
            remaining <= MAX_DAILY_WORK_MINUTES ->
                TodayGoal.WeekFull(endTimeForTarget(start, entry.manualBreakMinutes, remaining, settings))
            else -> TodayGoal.DailyTarget(
                endTimeForTarget(start, entry.manualBreakMinutes, settings.dailyTargetMinutes, settings),
            )
        }
    }

    fun endTimeForTarget(start: LocalTime, manualBreakMinutes: Int, targetMinutes: Int, settings: AppSettings): LocalTime {
        var attendance = targetMinutes.coerceAtLeast(0)
        while (attendance - BreakCalculator.deductedBreak(attendance, manualBreakMinutes, settings) < targetMinutes &&
            attendance < targetMinutes + 24 * 60
        ) {
            attendance++
        }
        return start.plusMinutes(attendance.toLong())
    }
}
