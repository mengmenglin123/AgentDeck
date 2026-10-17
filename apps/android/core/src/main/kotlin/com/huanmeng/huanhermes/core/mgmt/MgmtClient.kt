package com.huanmeng.huanhermes.core.mgmt

import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.net.HostError
import com.huanmeng.huanhermes.core.net.Redactor
import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.time.OffsetDateTime
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Raw HTTP exchange; bodies are bytes so decoding never depends on a charset header. */
data class RawResponse(val status: Int, val body: ByteArray)

fun interface HttpEngine {
    suspend fun execute(method: String, url: String, headers: Map<String, String>, body: ByteArray?): RawResponse
}

class OkHttpEngine(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .build(),
) : HttpEngine {
    override suspend fun execute(method: String, url: String, headers: Map<String, String>, body: ByteArray?): RawResponse {
        val requestBody = body?.toRequestBody("application/json".toMediaType())
            ?: if (method == "POST" || method == "PATCH" || method == "PUT") ByteArray(0).toRequestBody() else null
        val request = Request.Builder().url(url).method(method, requestBody)
            .apply { headers.forEach { (k, v) -> header(k, v) } }.build()
        val call = client.newCall(request)
        return suspendCancellableCoroutine { cont ->
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) = cont.resumeWithException(e)
                override fun onResponse(call: Call, response: Response) {
                    val result = runCatching { response.use { RawResponse(it.code, it.body?.bytes() ?: ByteArray(0)) } }
                    result.fold(cont::resume, cont::resumeWithException)
                }
            })
        }
    }
}

data class ProjectInfo(val name: String, val agentType: String, val capabilities: List<String>, val models: List<String>)

data class SessionInfo(
    val id: String,
    val sessionKey: String,
    val project: String,
    val title: String?,
    val lastUser: String?,
    val updatedAt: Double?,
    val running: Boolean,
    val mode: String?,
    val model: String?,
    /** Optional overview from Hosts with the `session_overview` capability. */
    val status: String? = null,
    val preview: String? = null,
    val pendingPermissions: List<PendingPermission> = emptyList(),
) {
    val displayTitle: String
        get() = title?.trim()?.takeIf { it.isNotEmpty() }
            ?: lastUser?.trim()?.takeIf { it.isNotEmpty() }?.let { if (it.length > 40) it.take(40) + "…" else it }
            ?: sessionKey.substringAfterLast(':').take(16).ifEmpty { id }
}

/** A permission challenge the Host is still waiting on (from `/sessions`). */
data class PendingPermission(
    val id: String,
    val prompt: String,
    val replyCtx: String?,
    val buttons: List<com.huanmeng.huanhermes.core.protocol.FrameButton>,
)

data class TranscriptRow(val role: String, val content: String)

data class SessionDetail(
    val transcript: List<TranscriptRow>,
    val mode: String?,
    val model: String?,
    val workdir: String?,
    val capabilities: List<String>,
    val running: Boolean,
    /** v2 Hosts may report the journal position the transcript corresponds to. */
    val lastSeq: Long?,
)

interface MgmtApi {
    suspend fun status(): JsonObject
    suspend fun projects(): List<ProjectInfo>
    suspend fun sessions(project: String? = null): List<SessionInfo>
    suspend fun createSession(project: String, title: String? = null): SessionInfo
    suspend fun renameSession(id: String, title: String, project: String?): SessionInfo
    suspend fun deleteSession(id: String, project: String?)
    suspend fun sessionDetail(id: String, project: String?): SessionDetail
    /** File paths for `@` mentions (Hosts with `file_search`); empty when unsupported. */
    suspend fun searchFiles(project: String?, query: String, limit: Int = 30): List<String> = emptyList()
    /** Raw GET of a read-only catalog (`/agents?project=x`); the `data` object. */
    suspend fun get(pathAndQuery: String): JsonObject = throw HostError.Protocol("unsupported")
}

/**
 * Management REST client: envelope `{ok, data}`, both session path dialects
 * (`/projects/{name}/sessions` and flat `/sessions`), UTF-8 byte decoding, and
 * readable errors for non-JSON bodies (proxy HTML pages are truncated).
 */
class MgmtClient(
    private val config: HostConfig,
    private val engine: HttpEngine = OkHttpEngine(),
) : MgmtApi {
    @Volatile var dialect: String? = null
        private set

    override suspend fun status(): JsonObject = request("GET", "/status")

    override suspend fun get(pathAndQuery: String): JsonObject = request("GET", pathAndQuery)

    override suspend fun searchFiles(project: String?, query: String, limit: Int): List<String> {
        val qs = buildString {
            append("/files/search?q=").append(q(query.take(200))).append("&limit=").append(limit.coerceIn(1, 100))
            if (!project.isNullOrBlank()) append("&project=").append(q(project))
        }
        return (request("GET", qs)["files"] as? JsonArray).orEmpty().mapNotNull { e ->
            when (e) {
                is JsonObject -> e.s("path")
                is JsonPrimitive -> e.contentOrNull
                else -> null
            }?.takeIf { it.isNotBlank() && !it.startsWith("/") && !it.split('/').contains("..") }
        }
    }

    override suspend fun projects(): List<ProjectInfo> =
        (request("GET", "/projects")["projects"] as? JsonArray).orEmpty().mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            ProjectInfo(
                name = o.s("name").orEmpty(),
                agentType = (o.s("agent_type") ?: o.s("agentType")).orEmpty(),
                capabilities = strings(o["capabilities"]),
                models = strings(o["models"] ?: o["model_catalog"]),
            )
        }.filter { it.name.isNotEmpty() }

    override suspend fun sessions(project: String?): List<SessionInfo> {
        val proj = project?.trim().orEmpty()
        if (dialect == "project" && proj.isNotEmpty()) return projectSessions(proj)
        if (dialect == "flat") return flatSessions(proj)
        if (proj.isNotEmpty()) {
            try {
                return projectSessions(proj).also { dialect = "project" }
            } catch (e: HostError) {
                if (!looksMissing(e)) throw e
            }
        }
        return flatSessions(proj).also { dialect = "flat" }
    }

    private suspend fun flatSessions(project: String) =
        parseSessions(request("GET", "/sessions" + if (project.isEmpty()) "" else "?project=${q(project)}"), project)

    private suspend fun projectSessions(project: String) =
        parseSessions(request("GET", "/projects/${p(project)}/sessions"), project)

    override suspend fun createSession(project: String, title: String?): SessionInfo {
        val body = buildJsonObject {
            put("project", project)
            if (!title.isNullOrBlank()) { put("title", title); put("name", title) }
            put("session_key", "huanhermes-app:$project:${java.lang.Long.toHexString(System.nanoTime())}")
        }
        if (dialect != "flat") {
            try {
                val o = request("POST", "/projects/${p(project)}/sessions", body)
                dialect = "project"
                return session(o, project)
            } catch (e: HostError) {
                if (dialect == "project" || !looksMissing(e)) throw e
            }
        }
        val o = request("POST", "/sessions", body)
        dialect = "flat"
        return session(o, project)
    }

    override suspend fun renameSession(id: String, title: String, project: String?): SessionInfo {
        val body = buildJsonObject { put("title", title); put("name", title) }
        return session(sessionCall("PATCH", id, project, body), project.orEmpty())
    }

    override suspend fun deleteSession(id: String, project: String?) {
        sessionCall("DELETE", id, project, null)
    }

    override suspend fun sessionDetail(id: String, project: String?): SessionDetail {
        val o = sessionCall("GET", id, project, null)
        val rows = (o["transcript"] as? JsonArray).orEmpty().mapNotNull { e ->
            val r = e as? JsonObject ?: return@mapNotNull null
            TranscriptRow(r.s("role") ?: "system", r.s("content").orEmpty())
        }
        return SessionDetail(
            transcript = rows,
            mode = o.s("mode"), model = o.s("model"), workdir = o.s("workdir"),
            capabilities = strings(o["capabilities"]),
            running = o.b("running"),
            lastSeq = (o["last_seq"] as? JsonPrimitive)?.contentOrNull?.toLongOrNull(),
        )
    }

    private suspend fun sessionCall(method: String, id: String, project: String?, body: JsonObject?): JsonObject {
        val scoped = project?.takeIf { it.isNotBlank() }?.let { "/projects/${p(it)}/sessions/${p(id)}" }
        val flat = "/sessions/${p(id)}"
        if (dialect == "project" && scoped != null) return request(method, scoped, body)
        try {
            return request(method, flat, body)
        } catch (e: HostError) {
            if (scoped == null || !looksMissing(e)) throw e
        }
        return request(method, scoped, body).also { dialect = "project" }
    }

    // ---------------------------------------------------------------------

    suspend fun request(method: String, path: String, body: JsonObject? = null): JsonObject {
        val url = config.mgmtBaseUrl + path
        val headers = buildMap {
            put("Authorization", "Bearer ${config.mgmtToken}")
            put("Accept", "application/json")
            if (body != null) put("Content-Type", "application/json")
        }
        val response = try {
            withContext(Dispatchers.IO) {
                engine.execute(method, url, headers, body?.toString()?.toByteArray(Charsets.UTF_8))
            }
        } catch (e: HostError) {
            throw e
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            throw HostError.Disconnected(Redactor.redact(e, config.secrets))
        }
        return decode(response)
    }

    private fun decode(response: RawResponse): JsonObject {
        val text = String(response.body, Charsets.UTF_8) // JSON is UTF-8 (RFC 8259) whatever the header says
        val json = runCatching { ProtocolJson.parseToJsonElement(text) as? JsonObject }.getOrNull()
        val status = response.status
        if (status !in 200..299) {
            val message = json?.s("error") ?: summarizeBody(text, status)
            val safe = Redactor.redact(message, config.secrets)
            throw if (status == 401 || status == 403) HostError.Auth(safe) else HostError.Http(status, safe)
        }
        if (text.isBlank()) return JsonObject(emptyMap())
        if (json == null) throw HostError.Protocol("响应不是 JSON：" + Redactor.redact(summarizeBody(text, status), config.secrets))
        if (json["ok"] != null && !json.b("ok")) {
            throw HostError.Protocol(Redactor.redact(json.s("error") ?: "request failed", config.secrets))
        }
        return (json["data"] as? JsonObject) ?: if (json["ok"] == null) json else JsonObject(emptyMap())
    }

    companion object {
        const val ERROR_BODY_LIMIT = 200

        /** Short single-line form of an error body (HTML tags dropped, ~200 chars). */
        fun summarizeBody(text: String, status: Int): String {
            val plain = text.replace(Regex("(?is)<(script|style)[^>]*>.*?</\\1>"), " ")
                .replace(Regex("<[^>]+>"), " ")
                .replace(Regex("\\s+"), " ")
                .trim()
            if (plain.isEmpty()) return "HTTP $status"
            val clipped = if (plain.length > ERROR_BODY_LIMIT) plain.take(ERROR_BODY_LIMIT) + "…" else plain
            return "HTTP $status: $clipped"
        }

        private fun looksMissing(e: HostError): Boolean {
            if (e is HostError.Http && (e.status == 404 || e.status == 405)) return true
            val m = e.message.orEmpty().lowercase()
            return "404" in m || "not found" in m || "unknown" in m
        }

        private fun p(segment: String) = HostConfig.encode(segment)
        private fun q(value: String) = HostConfig.encode(value)

        private fun JsonObject.s(key: String): String? = when (val v = this[key]) {
            null, is JsonNull -> null
            is JsonPrimitive -> v.contentOrNull
            else -> v.toString()
        }

        private fun JsonObject.b(key: String) = (this[key] as? JsonPrimitive)?.booleanOrNull == true

        private fun strings(e: JsonElement?): List<String> = (e as? JsonArray).orEmpty().mapNotNull {
            when (it) {
                is JsonPrimitive -> it.contentOrNull
                is JsonObject -> it.s("id") ?: it.s("name") ?: it.s("model")
                else -> null
            }?.takeIf { s -> s.isNotBlank() }
        }

        private fun parseSessions(data: JsonObject, project: String): List<SessionInfo> =
            (data["sessions"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let { o -> session(o, project) } }

        internal fun session(o: JsonObject, project: String): SessionInfo {
            val sk = (o.s("session_key") ?: o.s("id")).orEmpty()
            val id = o.s("id") ?: sk
            val last = o.s("last_user")?.takeIf { it.isNotEmpty() } ?: when (val lm = o["last_message"]) {
                is JsonPrimitive -> lm.contentOrNull
                is JsonObject -> lm.s("content")
                else -> null
            }
            return SessionInfo(
                id = id,
                sessionKey = sk.ifEmpty { id },
                project = o.s("project")?.takeIf { it.isNotEmpty() } ?: project,
                title = o.s("title") ?: o.s("name") ?: o.s("chat_name"),
                lastUser = last,
                updatedAt = time(o["updated_at"] ?: o["updatedAt"]),
                running = o.b("running") || o.b("live") || o.b("active") || o.s("status") == "running",
                mode = o.s("mode"), model = o.s("model"),
                status = o.s("status")?.takeIf { it.isNotEmpty() },
                preview = (o.s("last_message_preview") ?: o.s("preview"))?.takeIf { it.isNotBlank() },
                pendingPermissions = (o["pending_permissions"] as? JsonArray).orEmpty().mapNotNull { pendingPermission(it) },
            )
        }

        private fun pendingPermission(e: JsonElement): PendingPermission? {
            val o = e as? JsonObject ?: return null
            val id = o.s("id")?.takeIf { it.isNotEmpty() } ?: return null
            val buttons = (o["buttons"] as? JsonArray).orEmpty().flatMap { row ->
                when (row) {
                    is JsonArray -> row.toList()
                    else -> listOf(row)
                }
            }.mapNotNull { b ->
                val bo = b as? JsonObject ?: return@mapNotNull null
                val data = bo.s("data")?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                com.huanmeng.huanhermes.core.protocol.FrameButton(bo.s("text") ?: data, data)
            }
            return PendingPermission(id, o.s("prompt").orEmpty(), o.s("reply_ctx"), buttons)
        }

        private fun time(e: JsonElement?): Double? {
            val p = e as? JsonPrimitive ?: return null
            p.doubleOrNull?.let { return it }
            return runCatching { OffsetDateTime.parse(p.content).toInstant().toEpochMilli() / 1000.0 }.getOrNull()
        }
    }
}
