package com.huanmeng.huanhermes.core.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

val ProtocolJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}

internal fun JsonObject.str(key: String): String? = when (val v = this[key]) {
    null, is JsonNull -> null
    is JsonPrimitive -> v.contentOrNull
    else -> v.toString()
}

internal fun JsonObject.text(key: String): String? = str(key)?.takeIf { it.isNotEmpty() }

internal fun JsonObject.bool(key: String): Boolean = (this[key] as? JsonPrimitive)?.booleanOrNull == true

internal fun JsonObject.long(key: String): Long? = when (val v = this[key]) {
    is JsonPrimitive -> if (v.isString) v.content.toLongOrNull() else v.longOrNull
    else -> null
}

/** Display form of a free-form value (`input`, `output`): strings as-is, JSON otherwise. */
internal fun JsonElement?.display(): String = when (this) {
    null, is JsonNull -> ""
    is JsonPrimitive -> contentOrNull.orEmpty()
    is JsonArray, is JsonObject -> toString()
}
