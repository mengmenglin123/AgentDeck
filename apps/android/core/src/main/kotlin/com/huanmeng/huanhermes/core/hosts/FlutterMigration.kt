package com.huanmeng.huanhermes.core.hosts

import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

/**
 * One-time import of the Flutter app's Host profiles (0.1.x) when the native
 * build is installed over it: public JSON from SharedPreferences
 * (`huan_profiles_public_v2`) + tokens from flutter_secure_storage
 * (`huan_p_<id>_bridge` / `_mgmt`). The deviceId is kept so the same
 * Host sessions stay visible.
 */
object FlutterMigration {
    const val PROFILES_KEY = "flutter.huan_profiles_public_v2"
    const val ACTIVE_KEY = "flutter.huan_active_profile_v2"
    /** flutter_secure_storage's fixed key prefix ("This is the prefix for a secure storage\n", base64). */
    const val SECURE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_"

    fun bridgeKey(id: String) = SECURE_PREFIX + "huan_p_${id}_bridge"
    fun mgmtKey(id: String) = SECURE_PREFIX + "huan_p_${id}_mgmt"

    fun parse(publicJson: String?, activeId: String?, secret: (String) -> String?): ProfilesSnapshot? {
        if (publicJson.isNullOrBlank()) return null
        val list = runCatching { ProtocolJson.parseToJsonElement(publicJson) as? JsonArray }.getOrNull() ?: return null
        val profiles = list.mapNotNull { item ->
            val o = item as? JsonObject ?: return@mapNotNull null
            val id = o.s("id")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val c = o["config"] as? JsonObject ?: o
            val host = c.s("host")?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val bridge = c.i("bridgePort")?.takeIf(HostConfig::validPort) ?: 9810
            val mgmt = c.i("mgmtPort")?.takeIf(HostConfig::validPort) ?: 9820
            val config = HostConfig(
                host = host, bridgePort = bridge, mgmtPort = mgmt,
                useTls = (c["useTls"] as? JsonPrimitive)?.booleanOrNull == true,
                platformName = c.s("platformName") ?: "huanhermes-app",
                deviceId = c.s("deviceId")?.takeIf { it.isNotBlank() } ?: HostConfig.newDeviceId(),
                bridgeToken = secret(bridgeKey(id)).orEmpty(),
                mgmtToken = secret(mgmtKey(id)).orEmpty(),
            )
            HostProfile(id = id, name = o.s("name")?.trim()?.takeIf { it.isNotEmpty() } ?: "Host", config = config)
        }
        if (profiles.isEmpty()) return null
        return ProfilesSnapshot(profiles, activeId?.takeIf { a -> profiles.any { it.id == a } } ?: profiles.first().id)
    }

    private fun JsonObject.s(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.i(k: String) = (this[k] as? JsonPrimitive)?.intOrNull
}
