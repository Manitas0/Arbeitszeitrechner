package de.arbeitszeitrechner.data

import android.content.Context
import androidx.core.content.edit
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.BreakRule
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalTime

/** Speichert Einträge und Einstellungen lokal in den SharedPreferences. */
class Repository(context: Context) {

    private val entryPrefs = context.getSharedPreferences("entries", Context.MODE_PRIVATE)
    private val settingsPrefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun loadEntries(): Map<LocalDate, DayEntry> =
        entryPrefs.all.mapNotNull { (key, value) ->
            val date = runCatching { LocalDate.parse(key) }.getOrNull() ?: return@mapNotNull null
            val json = value as? String ?: return@mapNotNull null
            runCatching { decode(date, JSONObject(json)) }.getOrNull()?.let { date to it }
        }.toMap()

    fun saveEntry(entry: DayEntry) {
        entryPrefs.edit {
            if (entry.isEmpty) remove(entry.date.toString())
            else putString(entry.date.toString(), encode(entry).toString())
        }
    }

    fun deleteEntry(date: LocalDate) {
        entryPrefs.edit { remove(date.toString()) }
    }

    fun loadSettings(): AppSettings {
        val defaults = AppSettings()
        val defaultRules = AppSettings.DEFAULT_BREAK_RULES
        return AppSettings(
            weeklyTargetMinutes = settingsPrefs.getInt("weeklyTargetMinutes", defaults.weeklyTargetMinutes),
            workDaysPerWeek = settingsPrefs.getInt("workDaysPerWeek", defaults.workDaysPerWeek),
            autoBreak = settingsPrefs.getBoolean("autoBreak", defaults.autoBreak),
            gradualDeduction = settingsPrefs.getBoolean("gradualDeduction", defaults.gradualDeduction),
            breakRules = defaultRules.mapIndexed { index, rule ->
                BreakRule(
                    afterMinutes = settingsPrefs.getInt("rule${index}After", rule.afterMinutes),
                    breakMinutes = settingsPrefs.getInt("rule${index}Break", rule.breakMinutes),
                )
            },
        )
    }

    fun saveSettings(settings: AppSettings) {
        settingsPrefs.edit {
            putInt("weeklyTargetMinutes", settings.weeklyTargetMinutes)
            putInt("workDaysPerWeek", settings.workDaysPerWeek)
            putBoolean("autoBreak", settings.autoBreak)
            putBoolean("gradualDeduction", settings.gradualDeduction)
            settings.breakRules.forEachIndexed { index, rule ->
                putInt("rule${index}After", rule.afterMinutes)
                putInt("rule${index}Break", rule.breakMinutes)
            }
        }
    }

    private fun encode(entry: DayEntry) = JSONObject().apply {
        put("type", entry.type.name)
        entry.start?.let { put("start", it.toString()) }
        entry.end?.let { put("end", it.toString()) }
        put("break", entry.manualBreakMinutes)
    }

    private fun decode(date: LocalDate, json: JSONObject) = DayEntry(
        date = date,
        type = runCatching { DayType.valueOf(json.optString("type")) }.getOrDefault(DayType.WORK),
        start = json.optString("start").takeIf { it.isNotEmpty() }?.let { LocalTime.parse(it) },
        end = json.optString("end").takeIf { it.isNotEmpty() }?.let { LocalTime.parse(it) },
        manualBreakMinutes = json.optInt("break", 0),
    )
}
