package software.primandproper.ngrams.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// The app icon's colors (ios/Tools/AppIcon.swift). Wallpaper-based dynamic color stays off so the
// brand color holds.
private val light =
    lightColorScheme(
        primary = Color(0xFF0F766E),
        onPrimary = Color.White,
        primaryContainer = Color(0xFFCCF0EA),
        onPrimaryContainer = Color(0xFF0F3D3A),
    )

private val dark =
    darkColorScheme(
        primary = Color(0xFF5EEAD4),
        onPrimary = Color(0xFF0F3D3A),
        primaryContainer = Color(0xFF1E2B30),
        onPrimaryContainer = Color(0xFF5EEAD4),
    )

@Composable
fun NgramsTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) dark else light, content = content)
}
