package de.arbeitszeitrechner.ui

import android.content.Context
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import de.arbeitszeitrechner.backup.BackupData
import de.arbeitszeitrechner.calc.formatTime
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.LocalDateTime

private class PendingRestore(val uri: Uri, val data: BackupData)

/** Einstellungen-Abschnitt: automatische Sicherung, Backup speichern und wiederherstellen. */
@Composable
fun BackupSection(viewModel: MainViewModel, onRestored: () -> Unit) {
    val context = LocalContext.current
    val status = viewModel.backupStatus
    var pendingRestore by remember { mutableStateOf<PendingRestore?>(null) }

    // Die automatische Sicherung schreibt im Hintergrund – Status regelmäßig nachladen.
    LaunchedEffect(Unit) {
        while (true) {
            delay(2_000)
            viewModel.refreshBackupStatus()
        }
    }

    val autoBackupLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json"),
    ) { uri -> if (uri != null) viewModel.enableAutoBackup(uri) }

    val saveLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json"),
    ) { uri ->
        if (uri != null) {
            viewModel.saveBackupTo(uri)
                .onSuccess { toast(context, "Backup gespeichert") }
                .onFailure { toast(context, "Backup konnte nicht gespeichert werden") }
        }
    }

    val restoreLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri != null) {
            viewModel.readBackup(uri)
                .onSuccess { pendingRestore = PendingRestore(uri, it) }
                .onFailure { toast(context, it.message ?: "Datei konnte nicht gelesen werden") }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionTitle("Daten sichern")
        SwitchRow(
            title = "Automatische Sicherung",
            description = "Nach jeder Änderung wird eine Sicherungsdatei aktualisiert, z. B. in " +
                "„Downloads“ oder Google Drive. Nach einer Neuinstallation einfach wiederherstellen.",
            checked = status.enabled,
            onCheckedChange = { on ->
                if (on) autoBackupLauncher.launch("Arbeitszeit-Backup.json") else viewModel.disableAutoBackup()
            },
        )
        if (status.enabled) {
            val error = status.error
            val lastSuccess = status.lastSuccess
            Text(
                text = when {
                    error != null -> error
                    lastSuccess != null -> "Zuletzt gesichert: ${formatDateTime(lastSuccess)}"
                    else -> "Wird gesichert …"
                },
                style = MaterialTheme.typography.bodySmall,
                color = if (error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
            )
            if (error != null) {
                TextButton(onClick = { autoBackupLauncher.launch("Arbeitszeit-Backup.json") }) {
                    Text("Neue Sicherungsdatei wählen")
                }
            }
        }
        OutlinedButton(
            onClick = { saveLauncher.launch("Arbeitszeit-Backup-${LocalDate.now()}.json") },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Backup jetzt speichern")
        }
        OutlinedButton(
            onClick = { restoreLauncher.launch(arrayOf("*/*")) },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Backup wiederherstellen")
        }
    }

    pendingRestore?.let { pending ->
        RestoreDialog(
            data = pending.data,
            offerAutoBackup = !status.enabled,
            onDismiss = { pendingRestore = null },
            onConfirm = { useForAutoBackup ->
                viewModel.restoreBackup(pending.data, if (useForAutoBackup) pending.uri else null)
                pendingRestore = null
                toast(context, "Backup wiederhergestellt")
                onRestored()
            },
        )
    }
}

@Composable
private fun RestoreDialog(
    data: BackupData,
    offerAutoBackup: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (useForAutoBackup: Boolean) -> Unit,
) {
    var useForAutoBackup by remember { mutableStateOf(offerAutoBackup) }
    val created = data.createdAt?.let { " vom ${formatDateTime(it)}" }.orEmpty()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Backup wiederherstellen?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "Sicherung$created mit ${data.entries.size} Einträgen. Einträge für dieselben Tage " +
                        "werden überschrieben, alle anderen bleiben erhalten. Die Einstellungen werden übernommen.",
                )
                if (offerAutoBackup) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .toggleable(
                                value = useForAutoBackup,
                                onValueChange = { useForAutoBackup = it },
                                role = Role.Checkbox,
                            ),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(checked = useForAutoBackup, onCheckedChange = null)
                        Text(
                            "Diese Datei für die automatische Sicherung verwenden",
                            modifier = Modifier.padding(start = 8.dp),
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(offerAutoBackup && useForAutoBackup) }) { Text("Wiederherstellen") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Abbrechen") }
        },
    )
}

private fun formatDateTime(dateTime: LocalDateTime): String =
    "${LONG_DATE.format(dateTime)}, ${formatTime(dateTime.toLocalTime())}"

internal fun toast(context: Context, message: String) {
    Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
}
