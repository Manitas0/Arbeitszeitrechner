package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import java.time.LocalTime

/** Was ein Tipp auf "Stempeln" (App, Widget, Schnelleinstellung) gerade bewirkt. */
enum class ClockAction(val label: String) {
    CLOCK_IN("Kommen"),
    CLOCK_OUT("Gehen"),
}

/** null: Heute ist schon fertig gestempelt oder ein Abwesenheitstag. */
fun nextClockAction(entry: DayEntry): ClockAction? = when {
    entry.type.isAbsence -> null
    entry.start == null -> ClockAction.CLOCK_IN
    entry.end == null -> ClockAction.CLOCK_OUT
    else -> null
}

fun applyClockAction(entry: DayEntry, action: ClockAction, time: LocalTime): DayEntry = when (action) {
    ClockAction.CLOCK_IN -> entry.copy(type = DayType.WORK, start = time, end = null)
    ClockAction.CLOCK_OUT -> entry.copy(end = time)
}
