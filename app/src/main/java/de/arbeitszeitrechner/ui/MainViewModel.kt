package de.arbeitszeitrechner.ui

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import de.arbeitszeitrechner.backup.BackupData
import de.arbeitszeitrechner.backup.BackupFormat
import de.arbeitszeitrechner.calc.MonthExport
import de.arbeitszeitrechner.calc.WorkCalculator
import de.arbeitszeitrechner.calc.germanMonthName
import de.arbeitszeitrechner.data.DataTransfer
import de.arbeitszeitrechner.data.Repository
import de.arbeitszeitrechner.data.TimeClock
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.widget.WorkWidgets
import java.time.LocalDate
import java.time.YearMonth

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = Repository(application)

    var entries by mutableStateOf(repository.loadEntries())
        private set
    var settings by mutableStateOf(repository.loadSettings())
        private set
    var weekStart by mutableStateOf(WorkCalculator.weekStartOf(LocalDate.now()))
        private set
    var backupStatus by mutableStateOf(repository.autoBackupStatus())
        private set

    private val app: Application get() = getApplication()

    fun entryFor(date: LocalDate): DayEntry = entries[date] ?: DayEntry(date)

    /** Daten neu laden, z. B. nachdem per Widget oder Schnelleinstellung gestempelt wurde. */
    fun reload() {
        entries = repository.loadEntries()
        settings = repository.loadSettings()
        backupStatus = repository.autoBackupStatus()
    }

    fun saveEntry(entry: DayEntry) {
        repository.saveEntry(entry)
        entries = if (entry.isEmpty) entries - entry.date else entries + (entry.date to entry)
        WorkWidgets.updateAll(app)
    }

    fun deleteEntry(date: LocalDate) {
        repository.deleteEntry(date)
        entries = entries - date
        WorkWidgets.updateAll(app)
    }

    fun updateSettings(newSettings: AppSettings) {
        repository.saveSettings(newSettings)
        settings = newSettings
        WorkWidgets.updateAll(app)
    }

    fun previousWeek() {
        weekStart = weekStart.minusWeeks(1)
    }

    fun nextWeek() {
        weekStart = weekStart.plusWeeks(1)
    }

    fun currentWeek() {
        weekStart = WorkCalculator.weekStartOf(LocalDate.now())
    }

    // --- Sicherung ---

    fun refreshBackupStatus() {
        backupStatus = repository.autoBackupStatus()
    }

    fun saveBackupTo(uri: Uri): Result<Unit> =
        runCatching { DataTransfer.writeText(app, uri, repository.createBackup()) }

    fun readBackup(uri: Uri): Result<BackupData> =
        runCatching { BackupFormat.parse(DataTransfer.readText(app, uri)) }

    /** Übernimmt die Sicherung und nutzt die Datei auf Wunsch für die automatische Sicherung. */
    fun restoreBackup(data: BackupData, autoBackupUri: Uri?) {
        repository.importBackup(data)
        autoBackupUri?.let(repository::enableAutoBackup)
        reload()
        WorkWidgets.updateAll(app)
    }

    fun enableAutoBackup(uri: Uri) {
        repository.enableAutoBackup(uri)
        refreshBackupStatus()
    }

    fun disableAutoBackup() {
        repository.disableAutoBackup()
        refreshBackupStatus()
    }

    // --- Monatsexport ---

    fun monthSummary(month: YearMonth): MonthExport.Summary = MonthExport.summary(month, entries, settings)

    fun saveMonthTo(month: YearMonth, uri: Uri): Result<Unit> =
        runCatching { DataTransfer.writeText(app, uri, MonthExport.csv(month, entries, settings)) }

    fun shareMonth(context: Context, month: YearMonth): Result<Unit> = runCatching {
        DataTransfer.shareFile(
            context = context,
            fileName = MonthExport.fileName(month),
            mimeType = "text/csv",
            content = MonthExport.csv(month, entries, settings),
            title = "Stundenzettel ${germanMonthName(month)}",
        )
    }

    /** Kommen bzw. Gehen für heute auf die aktuelle Uhrzeit stempeln. */
    fun toggleClock() {
        TimeClock.toggle(app)
        entries = repository.loadEntries()
    }
}
