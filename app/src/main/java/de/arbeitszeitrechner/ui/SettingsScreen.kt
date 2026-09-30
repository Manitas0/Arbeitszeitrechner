@file:OptIn(ExperimentalMaterial3Api::class)

package de.arbeitszeitrechner.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import de.arbeitszeitrechner.calc.formatDuration
import de.arbeitszeitrechner.calc.formatHoursInput
import de.arbeitszeitrechner.calc.parseHours
import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.BreakRule

@Composable
fun SettingsScreen(
    settings: AppSettings,
    onSave: (AppSettings) -> Unit,
    onBack: () -> Unit,
) {
    val rules = settings.breakRules
    var weeklyText by rememberSaveable { mutableStateOf(formatHoursInput(settings.weeklyTargetMinutes)) }
    var daysText by rememberSaveable { mutableStateOf(settings.workDaysPerWeek.toString()) }
    var isLimit by rememberSaveable { mutableStateOf(settings.weeklyHoursAreLimit) }
    var autoBreak by rememberSaveable { mutableStateOf(settings.autoBreak) }
    var gradual by rememberSaveable { mutableStateOf(settings.gradualDeduction) }
    var rule1After by rememberSaveable { mutableStateOf(formatHoursInput(rules[0].afterMinutes)) }
    var rule1Break by rememberSaveable { mutableStateOf(rules[0].breakMinutes.toString()) }
    var rule2After by rememberSaveable { mutableStateOf(formatHoursInput(rules[1].afterMinutes)) }
    var rule2Break by rememberSaveable { mutableStateOf(rules[1].breakMinutes.toString()) }

    val weekly = parseHours(weeklyText)?.takeIf { it in 1..7 * 24 * 60 }
    val days = daysText.toIntOrNull()?.takeIf { it in 1..7 }
    val r1After = parseHours(rule1After)?.takeIf { it in 0..24 * 60 }
    val r1Break = rule1Break.toIntOrNull()?.takeIf { it in 0..600 }
    val r2After = parseHours(rule2After)?.takeIf { it in 0..24 * 60 }
    val r2Break = rule2Break.toIntOrNull()?.takeIf { it in 0..600 }
    val rulesValid = r1After != null && r1Break != null && r2After != null && r2Break != null
    val valid = weekly != null && days != null && (!autoBreak || rulesValid)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Einstellungen") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SectionTitle("Arbeitszeit")
            OutlinedTextField(
                value = weeklyText,
                onValueChange = { weeklyText = it },
                label = { Text("Wochenarbeitszeit (Std.)") },
                supportingText = {
                    Text(
                        if (weekly == null) {
                            "Bitte z. B. 40, 38,5 oder 38:30 eingeben"
                        } else {
                            "Tagessoll: ${formatDuration(weekly / (days ?: 5))} h"
                        }
                    )
                },
                isError = weekly == null,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = daysText,
                onValueChange = { text -> daysText = text.filter(Char::isDigit).take(1) },
                label = { Text("Arbeitstage pro Woche") },
                supportingText = {
                    Text("Urlaub, Krankheit und Feiertage werden mit dem Tagessoll gutgeschrieben.")
                },
                isError = days == null,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            SwitchRow(
                title = "Wochenstunden sind Obergrenze",
                description = "Zum Beispiel die 20-Stunden-Grenze für Werkstudenten. Die App zeigt, " +
                    "wie viel bis zur Grenze fehlt, und warnt, wenn sie überschritten ist. " +
                    "Aus: Mehrarbeit wird als Überstunden angezeigt.",
                checked = isLimit,
                onCheckedChange = { isLimit = it },
            )

            HorizontalDivider()
            SectionTitle("Pausen")
            SwitchRow(
                title = "Pausen automatisch abziehen",
                description = "Die gesetzliche Mindestpause wird abgezogen, auch wenn keine oder " +
                    "eine kürzere Pause eingetragen ist.",
                checked = autoBreak,
                onCheckedChange = { autoBreak = it },
            )
            if (autoBreak) {
                RuleFields(
                    title = "Stufe 1",
                    afterText = rule1After,
                    onAfterChange = { rule1After = it },
                    afterError = r1After == null,
                    breakText = rule1Break,
                    onBreakChange = { rule1Break = it.filter(Char::isDigit).take(3) },
                    breakError = r1Break == null,
                )
                RuleFields(
                    title = "Stufe 2",
                    afterText = rule2After,
                    onAfterChange = { rule2After = it },
                    afterError = r2After == null,
                    breakText = rule2Break,
                    onBreakChange = { rule2Break = it.filter(Char::isDigit).take(3) },
                    breakError = r2Break == null,
                )
                SwitchRow(
                    title = "Gestaffelt abziehen",
                    description = "Es wird nur so viel Pause abgezogen, dass die Arbeitszeit nicht unter " +
                        "die Schwelle fällt (z. B. 6:15 h anwesend → 6:00 h Arbeitszeit), wie es das " +
                        "Arbeitszeitgesetz vorsieht. Aus: Die volle Pause wird abgezogen, sobald die " +
                        "Anwesenheit die Schwelle überschreitet.",
                    checked = gradual,
                    onCheckedChange = { gradual = it },
                )
                TextButton(
                    onClick = {
                        val defaults = AppSettings.DEFAULT_BREAK_RULES
                        rule1After = formatHoursInput(defaults[0].afterMinutes)
                        rule1Break = defaults[0].breakMinutes.toString()
                        rule2After = formatHoursInput(defaults[1].afterMinutes)
                        rule2Break = defaults[1].breakMinutes.toString()
                        gradual = true
                    },
                ) {
                    Text("Gesetzliche Werte wiederherstellen (§ 4 ArbZG)")
                }
            }

            Button(
                onClick = {
                    val newRules = if (rulesValid) {
                        listOf(BreakRule(r1After!!, r1Break!!), BreakRule(r2After!!, r2Break!!))
                    } else {
                        settings.breakRules
                    }
                    onSave(
                        AppSettings(
                            weeklyTargetMinutes = weekly!!,
                            workDaysPerWeek = days!!,
                            weeklyHoursAreLimit = isLimit,
                            autoBreak = autoBreak,
                            gradualDeduction = gradual,
                            breakRules = newRules,
                        )
                    )
                },
                enabled = valid,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Speichern")
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
}

@Composable
private fun SwitchRow(
    title: String,
    description: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .toggleable(value = checked, onValueChange = onCheckedChange, role = Role.Switch),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(end = 16.dp),
        ) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(checked = checked, onCheckedChange = null)
    }
}

@Composable
private fun RuleFields(
    title: String,
    afterText: String,
    onAfterChange: (String) -> Unit,
    afterError: Boolean,
    breakText: String,
    onBreakChange: (String) -> Unit,
    breakError: Boolean,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                value = afterText,
                onValueChange = onAfterChange,
                label = { Text("Ab mehr als (Std.)") },
                isError = afterError,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                value = breakText,
                onValueChange = onBreakChange,
                label = { Text("Pause (Min.)") },
                isError = breakError,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
        }
    }
}
