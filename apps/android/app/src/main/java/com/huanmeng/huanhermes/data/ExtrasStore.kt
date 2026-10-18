package com.huanmeng.huanhermes.data

import android.content.Context
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import com.huanmeng.huanhermes.core.overview.Automation
import com.huanmeng.huanhermes.core.overview.Automations
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/** Per-session goals and scheduled prompts; small, local, never sent anywhere by itself. */
class ExtrasStore(context: Context) {
    private val store = PreferenceDataStoreFactory.create(
        corruptionHandler = ReplaceFileCorruptionHandler { emptyPreferences() },
        produceFile = { context.applicationContext.preferencesDataStoreFile("extras") },
    )
    private val autoKey = stringPreferencesKey("automations")
    private fun goalKey(hostId: String, sessionId: String) = stringPreferencesKey("goal:$hostId|$sessionId")

    fun goal(hostId: String, sessionId: String): Flow<String?> =
        store.data.catch { emit(emptyPreferences()) }.map { it[goalKey(hostId, sessionId)]?.ifBlank { null } }

    suspend fun setGoal(hostId: String, sessionId: String, text: String?) = store.edit {
        if (text.isNullOrBlank()) it.remove(goalKey(hostId, sessionId)) else it[goalKey(hostId, sessionId)] = text.trim().take(500)
    }

    val automations: Flow<List<Automation>> = store.data.catch { emit(emptyPreferences()) }.map { Automations.decode(it[autoKey]) }

    suspend fun automationsNow(): List<Automation> = automations.first()

    suspend fun updateAutomations(transform: (List<Automation>) -> List<Automation>) = store.edit {
        it[autoKey] = Automations.encode(transform(Automations.decode(it[autoKey])))
    }
}
