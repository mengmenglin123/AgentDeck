package com.huanmeng.huanhermes.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
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

@Composable
fun HuanHermesTheme(settings: AppSettings, content: @Composable () -> Unit) {
    val dark = when (settings.themeMode) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val context = LocalContext.current
    // Full tonal schemes (every surfaceContainer role) generated from each preset's seed.
    val accented = when {
        settings.dynamicColor && !settings.highContrast && Build.VERSION.SDK_INT >= 31 ->
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        else -> Palettes.scheme(settings.themePreset, dark, settings.highContrast)
    }
    val finalScheme = if (dark && settings.amoledBlack) accented.copy(
        background = Color.Black,
        surface = Color.Black,
        surfaceContainerLowest = Color.Black,
        surfaceContainerLow = Color(0xFF0A0A0B),
        surfaceContainer = Color(0xFF111113),
        surfaceContainerHigh = Color(0xFF18181B),
        surfaceContainerHighest = Color(0xFF202024),
    ) else accented
    val base = LocalDensity.current
    CompositionLocalProvider(
        LocalDensity provides Density(base.density, base.fontScale * settings.fontScale),
        LocalHaptics provides settings.haptics,
    ) {
        MaterialTheme(colorScheme = finalScheme, typography = AppTypography, shapes = AppShapes, content = content)
    }
}

/** Rounder, softer containers. */
private val AppShapes = androidx.compose.material3.Shapes(
    extraSmall = androidx.compose.foundation.shape.RoundedCornerShape(8.dp),
    small = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
    medium = androidx.compose.foundation.shape.RoundedCornerShape(18.dp),
    large = androidx.compose.foundation.shape.RoundedCornerShape(24.dp),
    extraLarge = androidx.compose.foundation.shape.RoundedCornerShape(32.dp),
)

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

/** Accent presets (E4) layered on the brand scheme; dynamic colour wins when it is on. */
object ThemePresets {
    data class Preset(val id: String, val label: String, val light: Color, val dark: Color, val lightContainer: Color, val darkContainer: Color)

    val all = listOf(
        Preset("brand", "幻梦紫", Brand.accent, Brand.accentBright, Color(0xFFE8EAFF), Color(0xFF2A2F6B)),
        Preset("forest", "森林绿", Color(0xFF1E7A52), Color(0xFF4CC38A), Color(0xFFD5F2E3), Color(0xFF123D2A)),
        Preset("sunset", "落日橙", Color(0xFFB4541A), Color(0xFFF4955A), Color(0xFFFFE3D2), Color(0xFF4A2410)),
        Preset("ocean", "海湾蓝", Color(0xFF0B6BB8), Color(0xFF5AB0F2), Color(0xFFD6EBFC), Color(0xFF0D3355)),
        Preset("graphite", "石墨灰", Color(0xFF3C4148), Color(0xFFB7BDC6), Color(0xFFE3E5E8), Color(0xFF2C3036)),
    )

    fun apply(scheme: androidx.compose.material3.ColorScheme, id: String, dark: Boolean, dynamic: Boolean): androidx.compose.material3.ColorScheme {
        if (dynamic || id == "brand") return scheme
        val p = all.firstOrNull { it.id == id } ?: return scheme
        return scheme.copy(
            primary = if (dark) p.dark else p.light,
            primaryContainer = if (dark) p.darkContainer else p.lightContainer,
            onPrimaryContainer = if (dark) Color(0xFFF2F2F2) else Color(0xFF111418),
        )
    }
}
