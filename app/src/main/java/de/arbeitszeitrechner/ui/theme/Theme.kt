package de.arbeitszeitrechner.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val LightColors = lightColorScheme(
    primary = Color(0xFF1B6B5A),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFA6F2DC),
    onPrimaryContainer = Color(0xFF002019),
    secondary = Color(0xFF4B635B),
    secondaryContainer = Color(0xFFCDE8DD),
    onSecondaryContainer = Color(0xFF072019),
    tertiary = Color(0xFF416277),
    tertiaryContainer = Color(0xFFC5E7FF),
    onTertiaryContainer = Color(0xFF001E2D),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF8AD6C0),
    onPrimary = Color(0xFF00382D),
    primaryContainer = Color(0xFF005143),
    onPrimaryContainer = Color(0xFFA6F2DC),
    secondary = Color(0xFFB2CCC2),
    secondaryContainer = Color(0xFF344C44),
    onSecondaryContainer = Color(0xFFCDE8DD),
    tertiary = Color(0xFFA9CBE3),
    tertiaryContainer = Color(0xFF284A5E),
    onTertiaryContainer = Color(0xFFC5E7FF),
)

/** Farben für positive/negative Salden, passend zum Hell/Dunkel-Modus. */
@Immutable
data class BalanceColors(val positive: Color, val negative: Color)

val LocalBalanceColors = staticCompositionLocalOf {
    BalanceColors(positive = Color(0xFF1E7A3A), negative = Color(0xFFB3261E))
}

@Composable
fun ArbeitszeitTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColors
        else -> LightColors
    }
    val balanceColors = if (darkTheme) {
        BalanceColors(positive = Color(0xFF7DDB94), negative = Color(0xFFFFB4AB))
    } else {
        BalanceColors(positive = Color(0xFF1E7A3A), negative = Color(0xFFB3261E))
    }
    CompositionLocalProvider(LocalBalanceColors provides balanceColors) {
        MaterialTheme(colorScheme = colorScheme, content = content)
    }
}
