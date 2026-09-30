package de.arbeitszeitrechner.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.edit
import de.arbeitszeitrechner.backup.BackupData
import de.arbeitszeitrechner.backup.BackupFormat
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.BreakRule
import de.arbeitszeitrechner.model.DayEntry
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.concurrent.Executors

/** Zustand der automatischen Sicherung. */
data class AutoBackupStatus(
    val uri: Uri?,
    val lastSuccess: LocalDateTime?,
    val error: String?,
) {
    val enabled: Boolean get() = uri != null
}

/** Speichert Einträge und Einstellungen lokal in den SharedPreferences. */
class Repository(context: Context) {

    private val appContext = context.applicationContext
    private val entryPrefs = context.getSharedPreferences("entries", Context.MODE_PRIVATE)
    private val settingsPrefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val backupPrefs = context.getSharedPreferences("backup", Context.MODE_PRIVATE)

    fun loadEntries(): Map<LocalDate, DayEntry> =
        entryPrefs.all.mapNotNull { (key, value) ->
            val date = runCatching { LocalDate.parse(key) }.getOrNull() ?: return@mapNotNull null
            val json = value as? String ?: return@mapNotNull null
            runCatching { BackupFormat.decodeEntry(date, JSONObject(json)) }.getOrNull()?.let { date to it }
        }.toMap()

    fun loadEntry(date: LocalDate): DayEntry {
        val json = entryPrefs.getString(date.toString(), null) ?: return DayEntry(date)
        return runCatching { BackupFormat.decodeEntry(date, JSONObject(json)) }.getOrDefault(DayEntry(date))
    }

    fun saveEntry(entry: DayEntry) {
        entryPrefs.edit {
            if (entry.isEmpty) remove(entry.date.toString())
            else putString(entry.date.toString(), BackupFormat.encodeEntry(entry).toString())
        }
        autoBackup()
    }

    fun deleteEntry(date: LocalDate) {
        entryPrefs.edit { remove(date.toString()) }
        autoBackup()
    }

    fun loadSettings(): AppSettings {
        val defaults = AppSettings()
        val defaultRules = AppSettings.DEFAULT_BREAK_RULES
        return AppSettings(
            weeklyTargetMinutes = settingsPrefs.getInt("weeklyTargetMinutes", defaults.weeklyTargetMinutes),
            workDaysPerWeek = settingsPrefs.getInt("workDaysPerWeek", defaults.workDaysPerWeek),
            weeklyHoursAreLimit = settingsPrefs.getBoolean("weeklyHoursAreLimit", defaults.weeklyHoursAreLimit),
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
        writeSettings(settings)
        autoBackup()
    }

    private fun writeSettings(settings: AppSettings) {
        settingsPrefs.edit {
            putInt("weeklyTargetMinutes", settings.weeklyTargetMinutes)
            putInt("workDaysPerWeek", settings.workDaysPerWeek)
            putBoolean("weeklyHoursAreLimit", settings.weeklyHoursAreLimit)
            putBoolean("autoBreak", settings.autoBreak)
            putBoolean("gradualDeduction", settings.gradualDeduction)
            settings.breakRules.forEachIndexed { index, rule ->
                putInt("rule${index}After", rule.afterMinutes)
                putInt("rule${index}Break", rule.breakMinutes)
            }
        }
    }

    // --- Sicherung ---

    fun createBackup(): String =
        BackupFormat.create(loadEntries().values, loadSettings(), LocalDateTime.now())

    /**
     * Übernimmt eine Sicherung: Einträge aus der Sicherung ersetzen die Einträge derselben Tage,
     * alle anderen Tage bleiben erhalten. Die Einstellungen werden übernommen.
     */
    fun importBackup(data: BackupData) {
        entryPrefs.edit {
            data.entries.forEach { entry ->
                if (entry.isEmpty) remove(entry.date.toString())
                else putString(entry.date.toString(), BackupFormat.encodeEntry(entry).toString())
            }
        }
        data.settings?.let(::writeSettings)
        autoBackup()
    }

    fun autoBackupStatus(): AutoBackupStatus = AutoBackupStatus(
        uri = backupPrefs.getString(KEY_URI, null)?.let(Uri::parse),
        lastSuccess = backupPrefs.getString(KEY_LAST_SUCCESS, null)
            ?.let { runCatching { LocalDateTime.parse(it) }.getOrNull() },
        error = backupPrefs.getString(KEY_ERROR, null),
    )

    /** Schaltet die automatische Sicherung in die Datei [uri] ein und sichert sofort. */
    fun enableAutoBackup(uri: Uri) {
        runCatching {
            appContext.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }
        backupPrefs.edit {
            putString(KEY_URI, uri.toString())
            remove(KEY_ERROR)
        }
        autoBackup()
    }

    fun disableAutoBackup() {
        val uri = autoBackupStatus().uri ?: return
        runCatching {
            appContext.contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }
        backupPrefs.edit { clear() }
    }

    /** Schreibt die Sicherungsdatei im Hintergrund neu, falls die automatische Sicherung aktiv ist. */
    private fun autoBackup() {
        val uri = autoBackupStatus().uri ?: return
        val content = createBackup()
        backupWriter.execute {
            runCatching { DataTransfer.writeText(appContext, uri, content) }
                .onSuccess {
                    backupPrefs.edit {
                        putString(KEY_LAST_SUCCESS, LocalDateTime.now().withNano(0).toString())
                        remove(KEY_ERROR)
                    }
                }
                .onFailure {
                    backupPrefs.edit {
                        putString(KEY_ERROR, "Sicherungsdatei nicht erreichbar – bitte neu auswählen.")
                    }
                }
        }
    }

    private companion object {
        const val KEY_URI = "autoBackupUri"
        const val KEY_LAST_SUCCESS = "autoBackupLastSuccess"
        const val KEY_ERROR = "autoBackupError"

        /** Ein Thread für alle Schreibvorgänge, damit sich Sicherungen nicht überholen. */
        val backupWriter = Executors.newSingleThreadExecutor()
    }
}
