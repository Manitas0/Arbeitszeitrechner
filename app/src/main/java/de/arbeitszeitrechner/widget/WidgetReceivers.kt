package de.arbeitszeitrechner.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast
import de.arbeitszeitrechner.calc.ClockAction
import de.arbeitszeitrechner.calc.formatTime
import de.arbeitszeitrechner.data.TimeClock

/** Großes Widget: Wochenübersicht mit Kommen/Gehen-Knopf. */
class WeekWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        WorkWidgets.updateWeek(context, manager, appWidgetIds)
    }
}

/** Kleines Widget: ein Tipp zum Ein- oder Ausstempeln. */
class ClockWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        WorkWidgets.updateClock(context, manager, appWidgetIds)
    }
}

/** Empfängt Tipps auf die Stempel-Knöpfe der Widgets. */
class ClockToggleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE) return
        val (action, entry) = TimeClock.toggle(context) ?: return
        val message = when (action) {
            ClockAction.CLOCK_IN -> "Eingestempelt um ${entry.start?.let(::formatTime)}"
            ClockAction.CLOCK_OUT -> "Ausgestempelt um ${entry.end?.let(::formatTime)}"
        }
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
    }

    companion object {
        const val ACTION_TOGGLE = "de.arbeitszeitrechner.action.TOGGLE_CLOCK"
    }
}
