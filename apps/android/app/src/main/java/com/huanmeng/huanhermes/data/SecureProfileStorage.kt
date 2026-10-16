package com.huanmeng.huanhermes.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.huanmeng.huanhermes.core.hosts.ProfileStorage
import com.huanmeng.huanhermes.core.hosts.ProfilesSnapshot
import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Host profiles (tokens included) in EncryptedSharedPreferences. If the
 * Keystore key is gone (reinstall, restore, OEM bug) the file can't be
 * decrypted: it is wiped and recreated instead of crashing at startup.
 */
class SecureProfileStorage(private val context: Context) : ProfileStorage {
    @Volatile private var prefs: SharedPreferences? = null

    private fun open(): SharedPreferences {
        prefs?.let { return it }
        val app = context.applicationContext
        val created = try {
            create(app)
        } catch (e: Exception) {
            app.deleteSharedPreferences(FILE)
            runCatching { create(app) }.getOrElse {
                // Last resort: keep the app usable without persisted profiles.
                app.getSharedPreferences("$FILE-volatile", Context.MODE_PRIVATE).also { p -> p.edit().clear().apply() }
            }
        }
        prefs = created
        return created
    }

    private fun create(app: Context): SharedPreferences {
        val key = MasterKey.Builder(app).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        return EncryptedSharedPreferences.create(
            app, FILE, key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override suspend fun load(): ProfilesSnapshot = withContext(Dispatchers.IO) {
        runCatching {
            val raw = open().getString(KEY, null) ?: return@runCatching ProfilesSnapshot()
            ProtocolJson.decodeFromString(ProfilesSnapshot.serializer(), raw)
        }.getOrElse {
            runCatching { open().edit().remove(KEY).apply() }
            ProfilesSnapshot()
        }
    }

    override suspend fun save(snapshot: ProfilesSnapshot) = withContext(Dispatchers.IO) {
        runCatching {
            open().edit().putString(KEY, ProtocolJson.encodeToString(ProfilesSnapshot.serializer(), snapshot)).commit()
        }
        Unit
    }

    private companion object {
        const val FILE = "huanhermes_native_profiles"
        const val KEY = "profiles_v1"
    }
}
