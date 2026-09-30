@file:OptIn(ExperimentalMaterial3Api::class)

package de.arbeitszeitrechner.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.arbeitszeitrechner.calc.DayResult
import de.arbeitszeitrechner.calc.WeekSummary
import de.arbeitszeitrechner.calc.WorkCalculator
import de.arbeitszeitrechner.calc.formatDuration
import de.arbeitszeitrechner.calc.formatTime
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.DayType
import de.arbeitszeitrechner.ui.theme.LocalBalanceColors
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.LocalDateTime

@Composable
fun WeekScreen(viewModel: MainViewModel, onOpenSettings: () -> Unit) {
    val context = LocalContext.current
    var now by remember { mutableStateOf(LocalDateTime.now()) }
    LaunchedEffect(Unit) {
        // Laufende Arbeitszeit von heute regelmäßig aktualisieren.
        while (true) {
            delay(15_000)
            now = LocalDateTime.now()
        }
    }
    val today = now.toLocalDate()
    val settings = viewModel.settings
    val summary = WorkCalculator.summarizeWeek(viewModel.weekStart, viewModel.entries, settings, now)
    var editingDate by remember { mutableStateOf<LocalDate?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Arbeitszeitrechner") },
                actions = {
                    IconButton(onClick = { shareWeek(context, summary, settings.weeklyHoursAreLimit) }) {
                        Icon(Icons.Default.Share, contentDescription = "Woche teilen")
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Einstellungen")
                    }
                },
            )
        },
    ) { padding ->
        val layoutDirection = LocalLayoutDirection.current
        LazyColumn(
            contentPadding = PaddingValues(
                start = padding.calculateStartPadding(layoutDirection) + 16.dp,
                end = padding.calculateEndPadding(layoutDirection) + 16.dp,
                top = padding.calculateTopPadding() + 4.dp,
                bottom = padding.calculateBottomPadding() + 24.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                WeekNavigator(
                    weekStart = summary.weekStart,
                    isCurrentWeek = summary.weekStart == WorkCalculator.weekStartOf(today),
                    onPrevious = viewModel::previousWeek,
                    onNext = viewModel::nextWeek,
                    onToday = viewModel::currentWeek,
                )
            }
            item { SummaryCard(summary, isLimit = settings.weeklyHoursAreLimit) }
            items(summary.days, key = { it.entry.date.toString() }) { day ->
                DayCard(
                    day = day,
                    isToday = day.entry.date == today,
                    settings = settings,
                    onClick = { editingDate = day.entry.date },
                    onClockIn = viewModel::toggleClock,
                    onClockOut = viewModel::toggleClock,
                )
            }
            item {
                Text(
                    text = if (settings.autoBreak) {
                        "Pausen werden automatisch abgezogen (${breakRulesText(settings)}). " +
                            "Eine längere eingetragene Pause hat Vorrang."
                    } else {
                        "Automatischer Pausenabzug ist ausgeschaltet. Es wird nur die eingetragene Pause abgezogen."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }
    }

    editingDate?.let { date ->
        DayEditDialog(
            entry = viewModel.entryFor(date),
            settings = settings,
            onDismiss = { editingDate = null },
            onSave = {
                viewModel.saveEntry(it)
                editingDate = null
            },
            onDelete = {
                viewModel.deleteEntry(date)
                editingDate = null
            },
        )
    }
}

@Composable
private fun WeekNavigator(
    weekStart: LocalDate,
    isCurrentWeek: Boolean,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onToday: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onPrevious) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Vorherige Woche")
        }
        Column(
            modifier = Modifier.weight(1f),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("KW ${weekNumber(weekStart)}", style = MaterialTheme.typography.titleLarge)
            Text(
                weekRange(weekStart),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (!isCurrentWeek) {
                TextButton(onClick = onToday) { Text("Zur aktuellen Woche") }
            }
        }
        IconButton(onClick = onNext) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Nächste Woche")
        }
    }
}

@Composable
private fun SummaryCard(summary: WeekSummary, isLimit: Boolean) {
    val balanceColors = LocalBalanceColors.current
    val balance = summary.balanceMinutes
    val limitExceeded = isLimit && balance > 0
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Text("Arbeitszeit diese Woche", style = MaterialTheme.typography.labelLarge)
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    formatDuration(summary.actualMinutes),
                    style = MaterialTheme.typography.displayMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    " / ${formatDuration(summary.targetMinutes)} h",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
            }
            val progress = if (summary.targetMinutes > 0) {
                (summary.actualMinutes.toFloat() / summary.targetMinutes).coerceIn(0f, 1f)
            } else {
                1f
            }
            LinearProgressIndicator(
                progress = { progress },
                color = if (limitExceeded) balanceColors.negative else MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
            )
            Row {
                if (isLimit) {
                    if (limitExceeded) {
                        Stat(
                            "Grenze überschritten",
                            "+${formatDuration(balance)} h",
                            color = balanceColors.negative,
                            modifier = Modifier.weight(1f),
                        )
                    } else {
                        Stat("Bis zur Grenze", "${formatDuration(-balance)} h", modifier = Modifier.weight(1f))
                    }
                } else if (balance < 0) {
                    Stat("Noch offen", "${formatDuration(-balance)} h", modifier = Modifier.weight(1f))
                } else {
                    Stat(
                        "Überstunden",
                        "+${formatDuration(balance)} h",
                        color = balanceColors.positive,
                        modifier = Modifier.weight(1f),
                    )
                }
                Stat(
                    "Pausen abgezogen",
                    "${formatDuration(summary.breakMinutes)} h",
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun Stat(label: String, value: String, modifier: Modifier = Modifier, color: Color = Color.Unspecified) {
    Column(modifier = modifier) {
        Text(label, style = MaterialTheme.typography.labelMedium)
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = color)
    }
}

@Composable
private fun DayCard(
    day: DayResult,
    isToday: Boolean,
    settings: AppSettings,
    onClick: () -> Unit,
    onClockIn: () -> Unit,
    onClockOut: () -> Unit,
) {
    val entry = day.entry
    val colors = if (isToday) {
        CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
    } else {
        CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    }
    Card(onClick = onClick, colors = colors, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        if (isToday) "${dayName(entry.date)} · Heute" else dayName(entry.date),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        SHORT_DATE.format(entry.date),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                val hasValue = day.creditedMinutes > 0 || (entry.start != null && entry.end != null)
                Text(
                    if (hasValue || day.running) "${formatDuration(day.creditedMinutes)} h" else "–",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            DayDetail(day, settings)

            if (isToday && entry.type == DayType.WORK && (entry.start == null || entry.end == null)) {
                Spacer(modifier = Modifier.height(12.dp))
                if (entry.start == null) {
                    Button(onClick = onClockIn, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.size(ButtonDefaults.IconSpacing))
                        Text("Kommen – jetzt einstempeln")
                    }
                } else {
                    Button(onClick = onClockOut, modifier = Modifier.fillMaxWidth()) {
                        Text("Gehen – jetzt ausstempeln")
                    }
                }
            }
        }
    }
}

@Composable
private fun DayDetail(day: DayResult, settings: AppSettings) {
    val entry = day.entry
    val start = entry.start
    val end = entry.end
    val breakText = "Pause ${formatDuration(day.breakMinutes)} h" + if (day.autoBreakApplied) " (auto)" else ""
    val (text, color) = when {
        entry.type.isAbsence ->
            "${entry.type.label} · Tagessoll gutgeschrieben" to MaterialTheme.colorScheme.tertiary
        day.running && start != null -> {
            val target = WorkCalculator.endTimeForTarget(
                start, entry.manualBreakMinutes, settings.dailyTargetMinutes, settings,
            )
            "seit ${formatTime(start)} · $breakText\nTagessoll erreicht um ${formatTime(target)}" to
                MaterialTheme.colorScheme.primary
        }
        start != null && end != null ->
            "${formatTime(start)} – ${formatTime(end)} · $breakText" to MaterialTheme.colorScheme.onSurfaceVariant
        start != null ->
            "Beginn ${formatTime(start)} · Ende fehlt" to MaterialTheme.colorScheme.error
        end != null ->
            "Ende ${formatTime(end)} · Beginn fehlt" to MaterialTheme.colorScheme.error
        else ->
            "Kein Eintrag – tippen zum Erfassen" to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = color,
        modifier = Modifier.padding(top = 6.dp),
    )
    if (day.exceedsDailyMax) {
        Text(
            "Mehr als 10 h Arbeitszeit – gesetzliche Tageshöchstgrenze (§ 3 ArbZG)",
            style = MaterialTheme.typography.bodySmall,
            color = LocalBalanceColors.current.negative,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

private fun shareWeek(context: Context, summary: WeekSummary, isLimit: Boolean) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "Arbeitszeit KW ${weekNumber(summary.weekStart)}")
        putExtra(Intent.EXTRA_TEXT, weekShareText(summary, isLimit))
    }
    context.startActivity(Intent.createChooser(intent, "Woche teilen"))
}
