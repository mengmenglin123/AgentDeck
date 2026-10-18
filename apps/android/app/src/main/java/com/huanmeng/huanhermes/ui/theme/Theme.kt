package com.huanmeng.huanhermes.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.huanmeng.huanhermes.data.AppSettings
import com.huanmeng.huanhermes.data.ThemeMode

// Brand tokens carried over from the Flutter theme (former Flutter app_theme.dart).
object Brand {
    val accent = Color(0xFF5E6AD2)
    val accentBright = Color(0xFF7170FF)
    val accentSoft = Color(0xFF828FFF)
    val darkCanvas = Color(0xFF08090A)
    val darkPanel = Color(0xFF0F1011)
    val darkSurface = Color(0xFF191A1B)
    val darkElevated = Color(0xFF28282C)
    val lightCanvas = Color(0xFFF7F8F8)
    val lightSurface = Color(0xFFFFFFFF)
    val lightMuted = Color(0xFFF3F4F5)
    val success = Color(0xFF10B981)
    val warning = Color(0xFFF59E0B)
    val danger = Color(0xFFEF4444)
}

private fun light(highContrast: Boolean) = lightColorScheme(
    primary = if (highContrast) Color(0xFF2F3AA8) else Brand.accent,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE8EAFF),
    onPrimaryContainer = Color(0xFF1A1F5C),
    secondary = Color(0xFF5B6170),
    secondaryContainer = Color(0xFFE8EAEE),
    onSecondaryContainer = Color(0xFF2A2E38),
    tertiaryContainer = Color(0xFFECEBFF),
    background = Brand.lightCanvas,
    surface = Brand.lightSurface,
    surfaceVariant = Brand.lightMuted,
    onSurface = if (highContrast) Color.Black else Color(0xFF1B1C1F),
    onSurfaceVariant = if (highContrast) Color(0xFF202124) else Color(0xFF5B6170),
    error = Brand.danger,
)

private fun dark(highContrast: Boolean) = darkColorScheme(
    primary = if (highContrast) Brand.accentSoft else Brand.accentBright,
    onPrimary = Color.White,
    primaryContainer = Color(0xFF2A2F6B),
    onPrimaryContainer = Color(0xFFE0E3FF),
    secondary = Color(0xFFA9AEBB),
    secondaryContainer = Brand.darkElevated,
    background = Brand.darkCanvas,
    surface = Brand.darkPanel,
    surfaceVariant = Brand.darkSurface,
    surfaceContainer = Brand.darkSurface,
    surfaceContainerHigh = Brand.darkElevated,
    onSurface = if (highContrast) Color.White else Color(0xFFE6E7EA),
    onSurfaceVariant = if (highContrast) Color(0xFFE0E0E0) else Color(0xFF9EA3AE),
    error = Brand.danger,
)

@Composable
fun HuanHermesTheme(settings: AppSettings, content: @Composable () -> Unit) {
    val dark = when (settings.themeMode) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val context = LocalContext.current
    val scheme = when {
        settings.dynamicColor && !settings.highContrast && Build.VERSION.SDK_INT >= 31 ->
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> dark(settings.highContrast)
        else -> light(settings.highContrast)
    }
    val finalScheme = if (dark && settings.amoledBlack) scheme.copy(
        background = Color.Black,
        surface = Color.Black,
        surfaceContainerLowest = Color.Black,
        surfaceContainerLow = Color(0xFF0A0A0B),
        surfaceContainer = Color(0xFF111113),
        surfaceContainerHigh = Color(0xFF18181B),
        surfaceContainerHighest = Color(0xFF202024),
    ) else scheme
    val base = LocalDensity.current
    CompositionLocalProvider(
        LocalDensity provides Density(base.density, base.fontScale * settings.fontScale),
        LocalHaptics provides settings.haptics,
    ) {
        MaterialTheme(colorScheme = finalScheme, typography = AppTypography, content = content)
    }
}

/** Slightly tighter titles and roomier body text for long agent output. */
private val AppTypography = androidx.compose.material3.Typography().let { t ->
    t.copy(
        titleLarge = t.titleLarge.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
        titleMedium = t.titleMedium.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
        bodyLarge = t.bodyLarge.copy(lineHeight = androidx.compose.ui.unit.TextUnit(24f, androidx.compose.ui.unit.TextUnitType.Sp)),
        bodyMedium = t.bodyMedium.copy(lineHeight = androidx.compose.ui.unit.TextUnit(21f, androidx.compose.ui.unit.TextUnitType.Sp)),
    )
}

/** Haptics that respect the user's setting. */
val LocalHaptics = androidx.compose.runtime.staticCompositionLocalOf { true }
