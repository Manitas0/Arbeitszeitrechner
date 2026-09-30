package de.arbeitszeitrechner.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import de.arbeitszeitrechner.MainActivity
import de.arbeitszeitrechner.R
import de.arbeitszeitrechner.calc.ClockAction
import de.arbeitszeitrechner.calc.DayResult
import de.arbeitszeitrechner.calc.WeekSummary
import de.arbeitszeitrechner.calc.WorkCalculator
import de.arbeitszeitrechner.calc.formatDuration
import de.arbeitszeitrechner.calc.formatTime
import de.arbeitszeitrechner.calc.nextClockAction
import de.arbeitszeitrechner.calc.todayStatusText
import de.arbeitszeitrechner.calc.weekStatusText
import de.arbeitszeitrechner.data.Repository
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.ui.weekNumber
import java.time.LocalDate

/** Daten, die die Widgets anzeigen. */
private class WidgetSnapshot(
    val settings: AppSettings,
    /** Woche ohne die gerade laufende Zeit – so stimmt die Summe auch zwischen zwei Aktualisierungen. */
    val summary: WeekSummary,
    val today: DayResult,
    val action: ClockAction?,
) {
    val limitExceeded: Boolean
        get() = settings.weeklyHoursAreLimit && summary.balanceMinutes > 0

    val progressPermille: Int
        get() = if (summary.targetMinutes > 0) {
            (summary.actualMinutes * 1000L / summary.targetMinutes).toInt().coerceIn(0, 1000)
        } else {
            1000
        }

    companion object {
        fun load(context: Context): WidgetSnapshot {
            val repository = Repository(context)
            val settings = repository.loadSettings()
            val entries = repository.loadEntries()
            val today = LocalDate.now()
            val summary = WorkCalculator.summarizeWeek(WorkCalculator.weekStartOf(today), entries, settings)
            val todayEntry = repository.loadEntry(today)
            return WidgetSnapshot(
                settings = settings,
                summary = summary,
                today = WorkCalculator.evaluate(todayEntry, settings),
                action = nextClockAction(todayEntry),
            )
        }
    }
}

object WorkWidgets {

    /** Alle Widgets neu zeichnen, z. B. nach einer Änderung in der App. */
    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val weekIds = manager.getAppWidgetIds(ComponentName(context, WeekWidgetProvider::class.java))
        val clockIds = manager.getAppWidgetIds(ComponentName(context, ClockWidgetProvider::class.java))
        if (weekIds.isEmpty() && clockIds.isEmpty()) return
        val snapshot = WidgetSnapshot.load(context)
        if (weekIds.isNotEmpty()) manager.updateAppWidget(weekIds, weekViews(context, snapshot))
        if (clockIds.isNotEmpty()) manager.updateAppWidget(clockIds, clockViews(context, snapshot))
    }

    internal fun updateWeek(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.updateAppWidget(ids, weekViews(context, WidgetSnapshot.load(context)))
    }

    internal fun updateClock(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.updateAppWidget(ids, clockViews(context, WidgetSnapshot.load(context)))
    }

    private fun weekViews(context: Context, s: WidgetSnapshot): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_week).apply {
            setTextViewText(R.id.widget_title, "KW ${weekNumber(s.summary.weekStart)} · Arbeitszeit")
            setTextViewText(R.id.widget_week_hours, "${formatDuration(s.summary.actualMinutes)} h")
            setTextViewText(R.id.widget_week_target, " / ${formatDuration(s.summary.targetMinutes)} h")

            val over = s.limitExceeded
            setViewVisibility(R.id.widget_progress, if (over) View.GONE else View.VISIBLE)
            setViewVisibility(R.id.widget_progress_over, if (over) View.VISIBLE else View.GONE)
            setProgressBar(
                if (over) R.id.widget_progress_over else R.id.widget_progress,
                1000, s.progressPermille, false,
            )

            setTextViewText(R.id.widget_balance, weekStatusText(s.summary, s.settings.weeklyHoursAreLimit))
            setTextColor(
                R.id.widget_balance,
                context.getColor(if (over) R.color.widget_warning else R.color.widget_text_secondary),
            )
            setTextViewText(R.id.widget_today, todayStatusText(s.today, s.settings))

            val action = s.action
            if (action != null) {
                setViewVisibility(R.id.widget_button, View.VISIBLE)
                setTextViewText(R.id.widget_button, action.label)
                setOnClickPendingIntent(R.id.widget_button, toggleIntent(context))
            } else {
                setViewVisibility(R.id.widget_button, View.GONE)
            }
            setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
        }

    private fun clockViews(context: Context, s: WidgetSnapshot): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_clock).apply {
            val action = s.action
            val entry = s.today.entry
            val week = "Woche ${formatDuration(s.summary.actualMinutes)} / ${formatDuration(s.summary.targetMinutes)} h"
            val title: String
            val subtitle: String
            when {
                action == ClockAction.CLOCK_IN -> {
                    title = ClockAction.CLOCK_IN.label
                    subtitle = week
                }
                action == ClockAction.CLOCK_OUT && entry.start != null -> {
                    title = ClockAction.CLOCK_OUT.label
                    subtitle = "seit ${formatTime(entry.start)}"
                }
                entry.type.isAbsence -> {
                    title = entry.type.label
                    subtitle = week
                }
                else -> {
                    title = "Heute ${formatDuration(s.today.creditedMinutes)} h"
                    subtitle = week
                }
            }
            setTextViewText(R.id.widget_clock_title, title)
            setTextViewText(R.id.widget_clock_subtitle, subtitle)

            val active = action != null
            setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (active) R.drawable.widget_accent_background else R.drawable.widget_background,
            )
            val titleColor = if (active) R.color.widget_on_accent else R.color.widget_text
            val subtitleColor = if (active) R.color.widget_on_accent else R.color.widget_text_secondary
            setTextColor(R.id.widget_clock_title, context.getColor(titleColor))
            setTextColor(R.id.widget_clock_subtitle, context.getColor(subtitleColor))
            setOnClickPendingIntent(
                R.id.widget_root,
                if (active) toggleIntent(context) else openAppIntent(context),
            )
        }

    private fun toggleIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, ClockToggleReceiver::class.java).setAction(ClockToggleReceiver.ACTION_TOGGLE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    internal fun openAppIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
