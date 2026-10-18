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
import kotlinx.coroutines.flow.first

enum class ThemeMode { SYSTEM, LIGHT, DARK }

data class AppSettings(
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val dynamicColor: Boolean = false,
    val highContrast: Boolean = false,
    val fontScale: Float = 1.0f,
    /** Pure black backgrounds in dark mode (OLED). */
    val amoledBlack: Boolean = false,
    /** Haptic feedback on send, approve and long-press. */
    val haptics: Boolean = true,
    /** Fold each finished turn's tool calls into one line. */
    val foldTurns: Boolean = true,
    /** Notify about pending approvals while the app is in the background. */
    val approvalNotifications: Boolean = true,
    /** The notification permission prompt was shown once already. */
    val askedNotificationPermission: Boolean = false,
    /** UnifiedPush endpoint from the distributor (ntfy etc.); null = not registered. */
    val pushEndpoint: String? = null,
    /** Foreground service that keeps checking while the app is closed. */
    val keepAlive: Boolean = false,
    /** Keep the screen on while the app is in front (long runs, terminal). */
    val keepScreenOn: Boolean = false,
    /** Terminal font size in sp. */
    val terminalFontSp: Float = 13f,
    /** Dashboard refreshes itself every 30 s while open. */
    val dashboardAutoRefresh: Boolean = true,
    /** Denser session rows. */
    val compactList: Boolean = false,
    /** Order inside session groups. */
    val sessionSort: com.huanmeng.huanhermes.core.overview.SessionSort = com.huanmeng.huanhermes.core.overview.SessionSort.Recent,
    /** Monospace font for chat messages. */
    val monoChat: Boolean = false,
    /** Enter / the keyboard's send key sends instead of a new line. */
    val enterToSend: Boolean = false,
    /** One-tap prompts shown above an empty composer. */
    val quickMessages: List<String> = DEFAULT_QUICK,
    /** Line numbers in chat code blocks. */
    val codeLineNumbers: Boolean = false,
    /** Wrap long code lines instead of scrolling sideways. */
    val codeWrap: Boolean = false,
    /** "本会话允许" asks for the device lock first. */
    val confirmAllowAll: Boolean = true,
    /** Ask for the device lock when opening the app (after 60 s away). */
    val appLock: Boolean = false,
    /** Accent preset id (ThemePresets). */
    val themePreset: String = "brand",
)

/** UI preferences. A corrupt file is replaced with defaults instead of crashing. */
val DEFAULT_QUICK = listOf("继续", "运行测试并修复失败的用例", "总结一下本轮改动", "提交前先给我看 diff")

class SettingsRepository(context: Context) {
    private val store = PreferenceDataStoreFactory.create(
        corruptionHandler = ReplaceFileCorruptionHandler { emptyPreferences() },
        produceFile = { context.applicationContext.preferencesDataStoreFile("settings") },
    )

    val settings: Flow<AppSettings> = store.data
        .catch { emit(emptyPreferences()) }
        .map { it.toSettings() }

    /** Settings as JSON for backup (F6); never tokens, push endpoints or one-time flags. */
    suspend fun exportJson(): String {
        val prefs = store.data.catch { emit(emptyPreferences()) }.first()
        val obj = kotlinx.serialization.json.buildJsonObject {
            put("format", kotlinx.serialization.json.JsonPrimitive("huanhermes-settings"))
            put("version", kotlinx.serialization.json.JsonPrimitive(1))
            put("values", kotlinx.serialization.json.buildJsonObject {
                prefs.asMap().forEach { (k, v) ->
                    if (k.name in EXPORT_SKIP) return@forEach
                    when (v) {
                        is Boolean -> put(k.name, kotlinx.serialization.json.JsonPrimitive(v))
                        is Float -> put(k.name, kotlinx.serialization.json.JsonPrimitive(v))
                        is String -> put(k.name, kotlinx.serialization.json.JsonPrimitive(v))
                        else -> Unit
                    }
                }
            })
        }
        return obj.toString()
    }

    /** Restores an [exportJson] backup; unknown keys are ignored. Returns how many values were applied. */
    suspend fun importJson(raw: String): Int {
        val root = kotlinx.serialization.json.Json.parseToJsonElement(raw) as? kotlinx.serialization.json.JsonObject ?: error("不是设置备份文件")
        require((root["format"] as? kotlinx.serialization.json.JsonPrimitive)?.content == "huanhermes-settings") { "不是 HuanHermes 设置备份" }
        val values = root["values"] as? kotlinx.serialization.json.JsonObject ?: return 0
        var applied = 0
        store.edit { prefs ->
            values.forEach { (name, el) ->
                if (name in EXPORT_SKIP) return@forEach
                val p = el as? kotlinx.serialization.json.JsonPrimitive ?: return@forEach
                STRING_KEYS[name]?.let { k -> if (p.isString) { prefs[k] = p.content; applied++ } }
                BOOL_KEYS[name]?.let { k -> p.content.toBooleanStrictOrNull()?.let { prefs[k] = it; applied++ } }
                FLOAT_KEYS[name]?.let { k -> p.content.toFloatOrNull()?.let { prefs[k] = it; applied++ } }
            }
        }
        return applied
    }

    suspend fun update(transform: (AppSettings) -> AppSettings) {
        store.edit { prefs ->
            val next = transform(prefs.toSettings())
            prefs[THEME] = next.themeMode.name
            prefs[DYNAMIC] = next.dynamicColor
            prefs[CONTRAST] = next.highContrast
            prefs[FONT] = next.fontScale.coerceIn(MIN_FONT, MAX_FONT)
            prefs[AMOLED] = next.amoledBlack
            prefs[HAPTICS] = next.haptics
            prefs[FOLD] = next.foldTurns
            prefs[NOTIFY] = next.approvalNotifications
            prefs[ASKED] = next.askedNotificationPermission
            if (next.pushEndpoint == null) prefs.remove(PUSH) else prefs[PUSH] = next.pushEndpoint
            prefs[KEEP] = next.keepAlive
            prefs[SCREEN] = next.keepScreenOn
            prefs[TERMFONT] = next.terminalFontSp.coerceIn(10f, 20f)
            prefs[DASHAUTO] = next.dashboardAutoRefresh
            prefs[COMPACT] = next.compactList
            prefs[SORT] = next.sessionSort.name
            prefs[MONO] = next.monoChat
            prefs[ENTER] = next.enterToSend
            prefs[QUICK] = next.quickMessages.map { it.replace('\n', ' ').trim() }.filter { it.isNotEmpty() }.take(8).joinToString("\n")
            prefs[LINENO] = next.codeLineNumbers
            prefs[WRAP] = next.codeWrap
            prefs[CONFIRM_ALL] = next.confirmAllowAll
            prefs[APPLOCK] = next.appLock
            prefs[PRESET] = next.themePreset
        }
    }

    private fun Preferences.toSettings() = AppSettings(
        themeMode = runCatching { ThemeMode.valueOf(this[THEME] ?: "") }.getOrDefault(ThemeMode.SYSTEM),
        dynamicColor = this[DYNAMIC] ?: false,
        highContrast = this[CONTRAST] ?: false,
        fontScale = (this[FONT] ?: 1.0f).coerceIn(MIN_FONT, MAX_FONT),
        amoledBlack = this[AMOLED] ?: false,
        haptics = this[HAPTICS] ?: true,
        foldTurns = this[FOLD] ?: true,
        approvalNotifications = this[NOTIFY] ?: true,
        askedNotificationPermission = this[ASKED] ?: false,
        pushEndpoint = this[PUSH],
        keepAlive = this[KEEP] ?: false,
        keepScreenOn = this[SCREEN] ?: false,
        terminalFontSp = (this[TERMFONT] ?: 13f).coerceIn(10f, 20f),
        dashboardAutoRefresh = this[DASHAUTO] ?: true,
        compactList = this[COMPACT] ?: false,
        sessionSort = runCatching { com.huanmeng.huanhermes.core.overview.SessionSort.valueOf(this[SORT] ?: "") }.getOrDefault(com.huanmeng.huanhermes.core.overview.SessionSort.Recent),
        monoChat = this[MONO] ?: false,
        enterToSend = this[ENTER] ?: false,
        quickMessages = this[QUICK]?.split('\n')?.filter { it.isNotBlank() } ?: DEFAULT_QUICK,
        codeLineNumbers = this[LINENO] ?: false,
        codeWrap = this[WRAP] ?: false,
        confirmAllowAll = this[CONFIRM_ALL] ?: true,
        appLock = this[APPLOCK] ?: false,
        themePreset = this[PRESET] ?: "brand",
    )

    companion object {
        const val MIN_FONT = 0.85f
        const val MAX_FONT = 1.4f
        private val THEME = stringPreferencesKey("theme_mode")
        private val DYNAMIC = booleanPreferencesKey("dynamic_color")
        private val CONTRAST = booleanPreferencesKey("high_contrast")
        private val FONT = floatPreferencesKey("font_scale")
        private val AMOLED = booleanPreferencesKey("amoled_black")
        private val HAPTICS = booleanPreferencesKey("haptics")
        private val FOLD = booleanPreferencesKey("fold_turns")
        private val NOTIFY = booleanPreferencesKey("approval_notifications")
        private val ASKED = booleanPreferencesKey("asked_notification_permission")
        private val PUSH = androidx.datastore.preferences.core.stringPreferencesKey("push_endpoint")
        private val KEEP = booleanPreferencesKey("keep_alive")
        private val SCREEN = booleanPreferencesKey("keep_screen_on")
        private val TERMFONT = floatPreferencesKey("terminal_font_sp")
        private val DASHAUTO = booleanPreferencesKey("dashboard_auto_refresh")
        private val COMPACT = booleanPreferencesKey("compact_list")
        private val SORT = stringPreferencesKey("session_sort")
        private val MONO = booleanPreferencesKey("mono_chat")
        private val ENTER = booleanPreferencesKey("enter_to_send")
        private val QUICK = stringPreferencesKey("quick_messages")
        private val LINENO = booleanPreferencesKey("code_line_numbers")
        private val WRAP = booleanPreferencesKey("code_wrap")
        private val CONFIRM_ALL = booleanPreferencesKey("confirm_allow_all")
        private val APPLOCK = booleanPreferencesKey("app_lock")
        private val PRESET = stringPreferencesKey("theme_preset")
        private val EXPORT_SKIP = setOf("push_endpoint", "asked_notification_permission")
        private val STRING_KEYS by lazy { listOf(THEME, SORT, QUICK, PRESET).associateBy { it.name } }
        private val BOOL_KEYS by lazy {
            listOf(DYNAMIC, CONTRAST, AMOLED, HAPTICS, FOLD, NOTIFY, KEEP, SCREEN, DASHAUTO, COMPACT, MONO, ENTER, LINENO, WRAP, CONFIRM_ALL, APPLOCK)
                .associateBy { it.name }
        }
        private val FLOAT_KEYS by lazy { listOf(FONT, TERMFONT).associateBy { it.name } }
    }
}
