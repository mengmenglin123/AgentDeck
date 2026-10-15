package com.huanmeng.huanhermes.data

import android.content.Context
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map

enum class ThemeMode { SYSTEM, LIGHT, DARK }

data class AppSettings(
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val dynamicColor: Boolean = false,
    val highContrast: Boolean = false,
    val fontScale: Float = 1.0f,
)

/** UI preferences. A corrupt file is replaced with defaults instead of crashing. */
class SettingsRepository(context: Context) {
    private val store = PreferenceDataStoreFactory.create(
        corruptionHandler = ReplaceFileCorruptionHandler { emptyPreferences() },
        produceFile = { context.applicationContext.preferencesDataStoreFile("settings") },
    )

    val settings: Flow<AppSettings> = store.data
        .catch { emit(emptyPreferences()) }
        .map { it.toSettings() }

    suspend fun update(transform: (AppSettings) -> AppSettings) {
        store.edit { prefs ->
            val next = transform(prefs.toSettings())
            prefs[THEME] = next.themeMode.name
            prefs[DYNAMIC] = next.dynamicColor
            prefs[CONTRAST] = next.highContrast
            prefs[FONT] = next.fontScale.coerceIn(MIN_FONT, MAX_FONT)
        }
    }

    private fun Preferences.toSettings() = AppSettings(
        themeMode = runCatching { ThemeMode.valueOf(this[THEME] ?: "") }.getOrDefault(ThemeMode.SYSTEM),
        dynamicColor = this[DYNAMIC] ?: false,
        highContrast = this[CONTRAST] ?: false,
        fontScale = (this[FONT] ?: 1.0f).coerceIn(MIN_FONT, MAX_FONT),
    )

    companion object {
        const val MIN_FONT = 0.85f
        const val MAX_FONT = 1.4f
        private val THEME = stringPreferencesKey("theme_mode")
        private val DYNAMIC = booleanPreferencesKey("dynamic_color")
        private val CONTRAST = booleanPreferencesKey("high_contrast")
        private val FONT = floatPreferencesKey("font_scale")
    }
}
