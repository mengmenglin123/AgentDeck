package com.huanmeng.huanhermes.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.huanmeng.huanhermes.core.hosts.FlutterMigration
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
            val raw = open().getString(KEY, null) ?: return@runCatching migrateFromFlutter()
            ProtocolJson.decodeFromString(ProfilesSnapshot.serializer(), raw)
        }.getOrElse {
            runCatching { open().edit().remove(KEY).apply() }
            ProfilesSnapshot()
        }
    }

    /**
     * First start after installing over the Flutter build: import its Host
     * profiles once (tokens from flutter_secure_storage, same Keystore master key).
     */
    private fun migrateFromFlutter(): ProfilesSnapshot {
        val app = context.applicationContext
        val flags = app.getSharedPreferences("huanhermes_migration", Context.MODE_PRIVATE)
        if (flags.getBoolean("flutter_done", false)) return ProfilesSnapshot()
        val snapshot = runCatching {
            val prefs = app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val publicJson = prefs.getString(FlutterMigration.PROFILES_KEY, null) ?: return@runCatching null
            val secure = runCatching {
                val key = MasterKey.Builder(app).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
                EncryptedSharedPreferences.create(
                    app, "FlutterSecureStorage", key,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                )
            }.getOrNull()
            FlutterMigration.parse(publicJson, prefs.getString(FlutterMigration.ACTIVE_KEY, null)) { k -> runCatching { secure?.getString(k, null) }.getOrNull() }
        }.getOrNull()
        flags.edit().putBoolean("flutter_done", true).apply()
        if (snapshot == null) return ProfilesSnapshot()
        runCatching { open().edit().putString(KEY, ProtocolJson.encodeToString(ProfilesSnapshot.serializer(), snapshot)).commit() }
        return snapshot
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
