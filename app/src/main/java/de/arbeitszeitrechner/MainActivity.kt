package de.arbeitszeitrechner

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import de.arbeitszeitrechner.ui.MainViewModel
import de.arbeitszeitrechner.ui.SettingsScreen
import de.arbeitszeitrechner.ui.WeekScreen
import de.arbeitszeitrechner.ui.theme.ArbeitszeitTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ArbeitszeitTheme {
                App()
            }
        }
    }
}

@Composable
private fun App(viewModel: MainViewModel = viewModel()) {
    var showSettings by rememberSaveable { mutableStateOf(false) }
    if (showSettings) {
        BackHandler { showSettings = false }
        SettingsScreen(
            settings = viewModel.settings,
            onSave = {
                viewModel.updateSettings(it)
                showSettings = false
            },
            onBack = { showSettings = false },
        )
    } else {
        WeekScreen(viewModel = viewModel, onOpenSettings = { showSettings = true })
    }
}
