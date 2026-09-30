package de.arbeitszeitrechner.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import de.arbeitszeitrechner.calc.WorkCalculator
import de.arbeitszeitrechner.data.Repository
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import java.time.LocalDate
import java.time.LocalTime
import java.time.temporal.ChronoUnit

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = Repository(application)

    var entries by mutableStateOf(repository.loadEntries())
        private set
    var settings by mutableStateOf(repository.loadSettings())
        private set
    var weekStart by mutableStateOf(WorkCalculator.weekStartOf(LocalDate.now()))
        private set

    fun entryFor(date: LocalDate): DayEntry = entries[date] ?: DayEntry(date)

    fun saveEntry(entry: DayEntry) {
        repository.saveEntry(entry)
        entries = if (entry.isEmpty) entries - entry.date else entries + (entry.date to entry)
    }

    fun deleteEntry(date: LocalDate) {
        repository.deleteEntry(date)
        entries = entries - date
    }

    fun updateSettings(newSettings: AppSettings) {
        repository.saveSettings(newSettings)
        settings = newSettings
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

    /** Stempelt den Beginn (Kommen) für heute auf die aktuelle Uhrzeit. */
    fun clockIn() {
        val today = LocalDate.now()
        saveEntry(entryFor(today).copy(start = nowRounded(), end = null))
    }

    /** Stempelt das Ende (Gehen) für heute auf die aktuelle Uhrzeit. */
    fun clockOut() {
        val today = LocalDate.now()
        saveEntry(entryFor(today).copy(end = nowRounded()))
    }

    private fun nowRounded(): LocalTime = LocalTime.now().truncatedTo(ChronoUnit.MINUTES)
}
