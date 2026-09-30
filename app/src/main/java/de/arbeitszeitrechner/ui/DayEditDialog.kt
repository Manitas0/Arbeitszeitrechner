package de.arbeitszeitrechner.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import de.arbeitszeitrechner.calc.DayResult
import de.arbeitszeitrechner.calc.WorkCalculator
import de.arbeitszeitrechner.calc.formatDuration
import de.arbeitszeitrechner.calc.formatTime
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayEntry
import de.arbeitszeitrechner.model.DayType
import java.time.LocalDate
import java.time.LocalTime
import java.time.temporal.ChronoUnit

private enum class TimeField { START, END }

@Composable
fun DayEditDialog(
    entry: DayEntry,
    settings: AppSettings,
    onDismiss: () -> Unit,
    onSave: (DayEntry) -> Unit,
    onDelete: () -> Unit,
) {
    var type by remember { mutableStateOf(entry.type) }
    var start by remember { mutableStateOf(entry.start) }
    var end by remember { mutableStateOf(entry.end) }
    var breakText by remember {
        mutableStateOf(if (entry.manualBreakMinutes > 0) entry.manualBreakMinutes.toString() else "")
    }
    var picking by remember { mutableStateOf<TimeField?>(null) }

    val manualBreak = breakText.toIntOrNull() ?: 0
    val draft = if (type == DayType.WORK) {
        DayEntry(entry.date, type, start, end, manualBreak)
    } else {
        DayEntry(entry.date, type)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("${dayName(entry.date)}, ${LONG_DATE.format(entry.date)}") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    DayType.entries.forEach { option ->
                        FilterChip(
                            selected = type == option,
                            onClick = { type = option },
                            label = { Text(option.label) },
                        )
                    }
                }

                if (type == DayType.WORK) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        TimeButton(
                            label = "Beginn",
                            time = start,
                            onClick = { picking = TimeField.START },
                            onClear = { start = null },
                            modifier = Modifier.weight(1f),
                        )
                        TimeButton(
                            label = "Ende",
                            time = end,
                            onClick = { picking = TimeField.END },
                            onClear = { end = null },
                            modifier = Modifier.weight(1f),
                        )
                    }
                    OutlinedTextField(
                        value = breakText,
                        onValueChange = { text -> breakText = text.filter(Char::isDigit).take(3) },
                        label = { Text("Tatsächliche Pause (Min.)") },
                        placeholder = { Text("optional") },
                        supportingText = {
                            Text(
                                if (settings.autoBreak) {
                                    "Mindestens die gesetzliche Pause wird automatisch abgezogen."
                                } else {
                                    "Automatischer Pausenabzug ist ausgeschaltet."
                                }
                            )
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (start != null && end != null) {
                        CalculationPreview(WorkCalculator.evaluate(draft, settings))
                    }
                } else {
                    Text(
                        "${type.label}: Es werden ${formatDuration(settings.dailyTargetMinutes)} h " +
                            "(Tagessoll) gutgeschrieben.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(draft) }) { Text("Speichern") }
        },
        dismissButton = {
            Row {
                if (!entry.isEmpty) {
                    TextButton(onClick = onDelete) { Text("Löschen") }
                }
                TextButton(onClick = onDismiss) { Text("Abbrechen") }
            }
        },
    )

    picking?.let { field ->
        val initial = when (field) {
            TimeField.START -> start ?: defaultStart(entry.date)
            TimeField.END -> end ?: defaultEnd(entry.date, start, manualBreak, settings)
        }
        TimePickerDialog(
            title = if (field == TimeField.START) "Beginn" else "Ende",
            initial = initial,
            onDismiss = { picking = null },
            onConfirm = { time ->
                if (field == TimeField.START) start = time else end = time
                picking = null
            },
        )
    }
}

private fun nowIfToday(date: LocalDate): LocalTime? =
    if (date == LocalDate.now()) LocalTime.now().truncatedTo(ChronoUnit.MINUTES) else null

private fun defaultStart(date: LocalDate): LocalTime = nowIfToday(date) ?: LocalTime.of(8, 0)

private fun defaultEnd(date: LocalDate, start: LocalTime?, manualBreak: Int, settings: AppSettings): LocalTime =
    nowIfToday(date)
        ?: WorkCalculator.endTimeForTarget(start ?: LocalTime.of(8, 0), manualBreak, settings.dailyTargetMinutes, settings)

@Composable
private fun TimeButton(
    label: String,
    time: LocalTime?,
    onClick: () -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedCard(onClick = onClick, modifier = modifier) {
        Row(
            modifier = Modifier.padding(start = 14.dp, top = 8.dp, bottom = 8.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    label,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    time?.let(::formatTime) ?: "--:--",
                    style = MaterialTheme.typography.titleLarge,
                )
            }
            if (time != null) {
                IconButton(onClick = onClear, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.Default.Clear,
                        contentDescription = "$label löschen",
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun CalculationPreview(result: DayResult) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            PreviewRow("Anwesenheit", "${formatDuration(result.attendanceMinutes)} h")
            PreviewRow(
                if (result.autoBreakApplied) "− Pause (automatisch)" else "− Pause",
                "${formatDuration(result.breakMinutes)} h",
            )
            PreviewRow("= Arbeitszeit", "${formatDuration(result.creditedMinutes)} h", bold = true)
        }
    }
}

@Composable
private fun PreviewRow(label: String, value: String, bold: Boolean = false) {
    val weight = if (bold) FontWeight.SemiBold else FontWeight.Normal
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(label, fontWeight = weight, modifier = Modifier.weight(1f))
        Text(value, fontWeight = weight)
    }
}
