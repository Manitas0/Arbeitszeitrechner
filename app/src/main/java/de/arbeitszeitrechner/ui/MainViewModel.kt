package de.arbeitszeitrechner.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import de.arbeitszeitrechner.calc.WorkCalculator
import de.arbeitszeitrechner.data.Repository
import de.arbeitszeitrechner.data.TimeClock
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.widget.WorkWidgets
import java.time.LocalDate

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = Repository(application)

    var entries by mutableStateOf(repository.loadEntries())
        private set
    var settings by mutableStateOf(repository.loadSettings())
        private set
    var weekStart by mutableStateOf(WorkCalculator.weekStartOf(LocalDate.now()))
        private set

    fun entryFor(date: LocalDate): DayEntry = entries[date] ?: DayEntry(date)

    /** Daten neu laden, z. B. nachdem per Widget oder Schnelleinstellung gestempelt wurde. */
    fun reload() {
        entries = repository.loadEntries()
        settings = repository.loadSettings()
    }

    fun saveEntry(entry: DayEntry) {
        repository.saveEntry(entry)
        entries = if (entry.isEmpty) entries - entry.date else entries + (entry.date to entry)
        WorkWidgets.updateAll(getApplication<Application>())
    }

    fun deleteEntry(date: LocalDate) {
        repository.deleteEntry(date)
        entries = entries - date
        WorkWidgets.updateAll(getApplication<Application>())
    }

    fun updateSettings(newSettings: AppSettings) {
        repository.saveSettings(newSettings)
        settings = newSettings
        WorkWidgets.updateAll(getApplication<Application>())
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

    /** Kommen bzw. Gehen für heute auf die aktuelle Uhrzeit stempeln. */
    fun toggleClock() {
        TimeClock.toggle(getApplication<Application>())
        entries = repository.loadEntries()
    }
}
