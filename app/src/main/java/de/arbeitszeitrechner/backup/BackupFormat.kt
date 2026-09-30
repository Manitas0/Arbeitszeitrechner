package de.arbeitszeitrechner.backup

import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.BreakRule
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

/** Inhalt einer Sicherungsdatei. */
data class BackupData(
    val createdAt: LocalDateTime?,
    val settings: AppSettings?,
    val entries: List<DayEntry>,
)

/** JSON-Format für gespeicherte Einträge und Sicherungsdateien. */
object BackupFormat {

    private const val APP_ID = "Arbeitszeitrechner"
    private const val VERSION = 1

    fun encodeEntry(entry: DayEntry): JSONObject = JSONObject().apply {
        put("type", entry.type.name)
        entry.start?.let { put("start", it.toString()) }
        entry.end?.let { put("end", it.toString()) }
        put("break", entry.manualBreakMinutes)
    }

    fun decodeEntry(date: LocalDate, json: JSONObject) = DayEntry(
        date = date,
        type = runCatching { DayType.valueOf(json.optString("type")) }.getOrDefault(DayType.WORK),
        start = json.optString("start").takeIf { it.isNotEmpty() }?.let { LocalTime.parse(it) },
        end = json.optString("end").takeIf { it.isNotEmpty() }?.let { LocalTime.parse(it) },
        manualBreakMinutes = json.optInt("break", 0).coerceAtLeast(0),
    )

    private fun encodeSettings(settings: AppSettings) = JSONObject().apply {
        put("weeklyTargetMinutes", settings.weeklyTargetMinutes)
        put("workDaysPerWeek", settings.workDaysPerWeek)
        put("weeklyHoursAreLimit", settings.weeklyHoursAreLimit)
        put("autoBreak", settings.autoBreak)
        put("gradualDeduction", settings.gradualDeduction)
        put("breakRules", JSONArray().apply {
            settings.breakRules.forEach { rule ->
                put(JSONObject().put("after", rule.afterMinutes).put("break", rule.breakMinutes))
            }
        })
    }

    private fun decodeSettings(json: JSONObject): AppSettings {
        val defaults = AppSettings()
        val rulesJson = json.optJSONArray("breakRules")
        val rules = AppSettings.DEFAULT_BREAK_RULES.mapIndexed { index, default ->
            val rule = rulesJson?.optJSONObject(index)
            BreakRule(
                afterMinutes = rule?.optInt("after", default.afterMinutes) ?: default.afterMinutes,
                breakMinutes = rule?.optInt("break", default.breakMinutes) ?: default.breakMinutes,
            )
        }
        return AppSettings(
            weeklyTargetMinutes = json.optInt("weeklyTargetMinutes", defaults.weeklyTargetMinutes)
                .coerceIn(1, 7 * 24 * 60),
            workDaysPerWeek = json.optInt("workDaysPerWeek", defaults.workDaysPerWeek).coerceIn(1, 7),
            weeklyHoursAreLimit = json.optBoolean("weeklyHoursAreLimit", defaults.weeklyHoursAreLimit),
            autoBreak = json.optBoolean("autoBreak", defaults.autoBreak),
            gradualDeduction = json.optBoolean("gradualDeduction", defaults.gradualDeduction),
            breakRules = rules,
        )
    }

    fun create(entries: Collection<DayEntry>, settings: AppSettings, createdAt: LocalDateTime): String =
        JSONObject().apply {
            put("app", APP_ID)
            put("version", VERSION)
            put("createdAt", createdAt.withNano(0).toString())
            put("settings", encodeSettings(settings))
            put("entries", JSONArray().apply {
                entries.filterNot { it.isEmpty }.sortedBy { it.date }.forEach { entry ->
                    put(encodeEntry(entry).put("date", entry.date.toString()))
                }
            })
        }.toString(2)

    /** Liest eine Sicherungsdatei. Wirft [IllegalArgumentException], wenn es keine gültige Sicherung ist. */
    fun parse(text: String): BackupData {
        val json = runCatching { JSONObject(text.removePrefix("\uFEFF").trim()) }.getOrNull()
            ?.takeIf { it.optString("app") == APP_ID }
            ?: throw IllegalArgumentException("Das ist keine Sicherungsdatei des Arbeitszeitrechners.")
        val entriesJson = json.optJSONArray("entries") ?: JSONArray()
        val entries = (0 until entriesJson.length()).mapNotNull { index ->
            val item = entriesJson.optJSONObject(index) ?: return@mapNotNull null
            val date = runCatching { LocalDate.parse(item.optString("date")) }.getOrNull()
                ?: return@mapNotNull null
            runCatching { decodeEntry(date, item) }.getOrNull()
        }
        return BackupData(
            createdAt = runCatching { LocalDateTime.parse(json.optString("createdAt")) }.getOrNull(),
            settings = json.optJSONObject("settings")?.let(::decodeSettings),
            entries = entries,
        )
    }
}
