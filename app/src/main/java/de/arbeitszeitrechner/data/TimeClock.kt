package de.arbeitszeitrechner.data

import android.content.Context
import de.arbeitszeitrechner.calc.ClockAction
import de.arbeitszeitrechner.calc.applyClockAction
import de.arbeitszeitrechner.calc.nextClockAction
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.widget.WorkWidgets
import java.time.LocalDate
import java.time.LocalTime
import java.time.temporal.ChronoUnit

/** Kommen/Gehen stempeln – gemeinsam genutzt von App, Widgets und Schnelleinstellung. */
object TimeClock {

    fun today(context: Context): DayEntry = Repository(context).loadEntry(LocalDate.now())

    fun nextAction(context: Context): ClockAction? = nextClockAction(today(context))

    /**
     * Führt die nächste Stempel-Aktion für heute aus und aktualisiert die Widgets.
     * Liefert die ausgeführte Aktion und den neuen Eintrag, oder null, wenn nichts zu tun war.
     */
    fun toggle(context: Context): Pair<ClockAction, DayEntry>? {
        val repository = Repository(context)
        val entry = repository.loadEntry(LocalDate.now())
        val action = nextClockAction(entry) ?: return null
        val updated = applyClockAction(entry, action, LocalTime.now().truncatedTo(ChronoUnit.MINUTES))
        repository.saveEntry(updated)
        WorkWidgets.updateAll(context)
        return action to updated
    }
}
