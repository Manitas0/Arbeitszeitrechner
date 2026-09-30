package de.arbeitszeitrechner.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.arbeitszeitrechner.calc.MonthExport
import de.arbeitszeitrechner.calc.formatDuration
import de.arbeitszeitrechner.calc.germanMonthName
import java.time.YearMonth

/** Dialog zum Exportieren eines Monats als Stundenzettel (CSV). */
@Composable
fun MonthExportDialog(viewModel: MainViewModel, initialMonth: YearMonth, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var month by remember { mutableStateOf(initialMonth) }
    val summary = viewModel.monthSummary(month)

    val saveLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri ->
        if (uri != null) {
            viewModel.saveMonthTo(month, uri)
                .onSuccess { toast(context, "Stundenzettel gespeichert") }
                .onFailure { toast(context, "Stundenzettel konnte nicht gespeichert werden") }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Stundenzettel exportieren") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { month = month.minusMonths(1) }) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Vorheriger Monat")
                    }
                    Text(
                        germanMonthName(month),
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = { month = month.plusMonths(1) }) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Nächster Monat")
                    }
                }
                Text(
                    when {
                        summary.totalMinutes == 0 -> "Keine Einträge in diesem Monat."
                        summary.absenceMinutes == 0 ->
                            "${formatDuration(summary.workedMinutes)} h an ${summary.workDays} Arbeitstagen"
                        else ->
                            "${formatDuration(summary.workedMinutes)} h an ${summary.workDays} Arbeitstagen, " +
                                "dazu ${formatDuration(summary.absenceMinutes)} h Urlaub/Krank/Feiertag " +
                                "(gesamt ${formatDuration(summary.totalMinutes)} h)"
                    },
                    style = MaterialTheme.typography.bodyLarge,
                )
                Text(
                    "CSV-Datei für Excel, Numbers oder Google Tabellen – mit Kalenderwoche, Beginn, Ende, " +
                        "Pause und Stunden pro Tag sowie der Monatssumme.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = {
                            viewModel.shareMonth(context, month)
                                .onFailure { toast(context, "Teilen nicht möglich") }
                        },
                        enabled = summary.totalMinutes > 0,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("Teilen")
                    }
                    OutlinedButton(
                        onClick = { saveLauncher.launch(MonthExport.fileName(month)) },
                        enabled = summary.totalMinutes > 0,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("Speichern")
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Schließen") }
        },
    )
}
