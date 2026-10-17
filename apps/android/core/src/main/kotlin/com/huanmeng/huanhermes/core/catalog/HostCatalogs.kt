package com.huanmeng.huanhermes.core.catalog

import com.huanmeng.huanhermes.core.net.HostConfig
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/** One row of a read-only catalog page. */
data class CatalogEntry(
    val id: String,
    val title: String,
    val subtitle: String = "",
    /** Short chips (status, type, tags). */
    val chips: List<String> = emptyList(),
    /** Longer text shown when the row is expanded. */
    val body: String = "",
    /** info / warn / error / ok / off; drives the colour dot. */
    val level: String? = null,
    /** Unix seconds. */
    val ts: Double? = null,
    val details: List<Pair<String, String>> = emptyList(),
)

enum class CatalogKind(
    val title: String,
    val path: String,
    /** Host capability that advertises the endpoint; null = always try. */
    val capability: String?,
    val projectScoped: Boolean,
    val searchable: Boolean = false,
) {
    AGENTS("Agents", "/agents", null, true),
    SKILLS("Skills", "/skills", null, true, searchable = true),
    MCP("MCP", "/mcp", null, true),
    TOOLS("Tools", "/mcp", null, true, searchable = true),
    MEMORY("Memory", "/memory", "memory_readonly", true, searchable = true),
    CRON("Cron", "/cron", "cron_readonly", false),
    ACTIVITY("Activity", "/activity", "activity_readonly", false),
    LOGS("Logs", "/logs", "logs_readonly", false, searchable = true),
    AUDIT("Audit", "/audit", "audit_readonly", false),
    ;

    fun url(project: String?, extra: Map<String, String> = emptyMap()): String {
        val params = buildList {
            if (projectScoped && !project.isNullOrBlank()) add("project" to project)
            when (this@CatalogKind) {
                LOGS -> add("limit" to "200")
                ACTIVITY -> add("limit" to "100")
                AUDIT -> add("limit" to "200")
                else -> {}
            }
            extra.forEach { (k, v) -> if (v.isNotBlank()) add(k to v) }
        }
        return if (params.isEmpty()) path else path + "?" + params.joinToString("&") { (k, v) -> k + "=" + HostConfig.encode(v) }
    }
}

object HostCatalogs {
    fun parse(kind: CatalogKind, data: JsonObject): List<CatalogEntry> = when (kind) {
        CatalogKind.AGENTS -> data.arr("agents").map { a ->
            val name = a.s("name") ?: a.s("id") ?: "agent"
            CatalogEntry(
                id = a.s("id") ?: name, title = name,
                subtitle = listOfNotNull(a.s("type"), a.s("model"), a.s("provider")).filter { it.isNotBlank() }.distinct().joinToString(" · "),
                chips = listOfNotNull(a.s("status"), a.s("version")) + a.strings("capabilities"),
                level = statusLevel(a.s("status")),
            )
        } + data.arr("platforms").map { p ->
            val type = p.s("type") ?: p.s("platform") ?: "platform"
            CatalogEntry(id = "platform-$type", title = type, subtitle = "平台适配器",
                chips = listOfNotNull(if (p.b("connected") == true) "已连接" else if (p.b("connected") == false) "未连接" else null),
                level = if (p.b("connected") == false) "off" else "ok")
        }
        CatalogKind.SKILLS -> data.arr("skills").map { s ->
            val name = s.s("name") ?: "skill"
            CatalogEntry(id = name, title = name, subtitle = s.s("description").orEmpty(),
                chips = listOfNotNull(s.s("category"), s.s("source"), s.s("version")) + s.strings("tags"),
                body = s.s("description").orEmpty())
        }
        CatalogKind.MCP -> data.arr("servers").map { m ->
            val name = m.s("name") ?: "server"
            val tools = toolNames(m)
            val enabled = m.b("enabled")
            CatalogEntry(id = name, title = name, subtitle = m.s("description").orEmpty(),
                chips = listOfNotNull(m.s("kind"), m.s("status"), if (enabled == false) "已停用" else null, if (tools.isNotEmpty()) "${tools.size} 个工具" else null),
                body = tools.joinToString("\n"),
                level = if (enabled == false) "off" else statusLevel(m.s("status")))
        }
        CatalogKind.TOOLS -> data.arr("servers").flatMap { m ->
            val server = m.s("name") ?: "server"
            toolNames(m).map { t -> CatalogEntry(id = "$server/$t", title = t, subtitle = "来自 $server", chips = listOfNotNull(m.s("kind"))) }
        }
        CatalogKind.MEMORY -> data.arr("memories").map { m ->
            val title = m.s("title") ?: m.s("id") ?: "memory"
            CatalogEntry(id = m.s("id") ?: title, title = title, subtitle = m.s("content").orEmpty(),
                chips = listOfNotNull(m.s("scope"), m.s("type"), m.s("confidence")) + m.strings("tags"),
                body = m.s("content").orEmpty(), ts = m.d("updated_at"))
        }
        CatalogKind.CRON -> data.arr("jobs").map { j ->
            val name = j.s("name") ?: j.s("id") ?: "job"
            val enabled = j.b("enabled") != false
            CatalogEntry(id = j.s("id") ?: name, title = name,
                subtitle = listOfNotNull(j.s("schedule"), j.s("description")).joinToString(" · "),
                chips = listOfNotNull(if (enabled) "启用" else "停用", j.s("kind"), j.s("last_status")?.let { "上次 $it" }),
                level = if (!enabled) "off" else statusLevel(j.s("last_status")),
                ts = j.d("next_run_at"),
                details = listOfNotNull(
                    j.d("next_run_at")?.let { "下次运行" to it.toString() },
                    j.d("last_run_at")?.let { "上次运行" to it.toString() },
                ))
        }
        CatalogKind.ACTIVITY -> data.arr("events").mapIndexed { i, e ->
            CatalogEntry(id = e.s("id") ?: "act-$i", title = e.s("summary") ?: e.s("kind") ?: "event",
                subtitle = listOfNotNull(e.s("kind"), e.s("source")).joinToString(" · "),
                level = e.s("level"), ts = e.d("ts"))
        }
        CatalogKind.LOGS -> data.arr("logs").mapIndexed { i, l ->
            CatalogEntry(id = "log-$i", title = l.s("message").orEmpty(),
                subtitle = l.s("source") ?: l.s("logger") ?: l.s("component") ?: "",
                chips = listOfNotNull(l.s("level")), level = l.s("level"), ts = l.d("ts"))
        }
        CatalogKind.AUDIT -> data.arr("records").mapIndexed { i, r ->
            val decision = r.s("decision") ?: r.s("action") ?: "?"
            CatalogEntry(id = (r.s("request_id") ?: "a") + "-$i", title = decisionLabel(decision) + (r.s("scope")?.let { " · $it" } ?: ""),
                subtitle = r.s("session_key").orEmpty(),
                chips = listOfNotNull(r.s("action"), r.s("request_id")),
                level = when (decision) { "deny" -> "error"; "allow_all" -> "warn"; "allow" -> "ok"; else -> "info" },
                ts = r.d("ts"))
        }
    }

    fun filter(entries: List<CatalogEntry>, query: String): List<CatalogEntry> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return entries
        return entries.filter { e ->
            e.title.lowercase().contains(q) || e.subtitle.lowercase().contains(q) || e.body.lowercase().contains(q) ||
                e.chips.any { it.lowercase().contains(q) }
        }
    }

    /** Status page: ordered key/value rows plus capabilities. */
    fun statusRows(status: JsonObject): List<Pair<String, String>> = buildList {
        status.s("version")?.let { add("版本" to it) }
        status.d("uptime_seconds")?.let { add("运行时间" to formatUptime(it.toLong())) }
        status.d("projects_count")?.let { add("项目" to it.toLong().toString()) }
        status.d("sessions_count")?.let { add("会话" to it.toLong().toString()) }
        (status.d("active_runs") ?: status.d("active_sessions"))?.let { add("运行中" to it.toLong().toString()) }
        status.strings("connected_platforms").takeIf { it.isNotEmpty() }?.let { add("平台" to it.joinToString(", ")) }
    }

    fun capabilities(status: JsonObject): List<String> = status.strings("capabilities")

    fun formatUptime(seconds: Long): String {
        val d = seconds / 86400; val h = seconds % 86400 / 3600; val m = seconds % 3600 / 60
        return when {
            d > 0 -> "${d} 天 ${h} 小时"
            h > 0 -> "${h} 小时 ${m} 分"
            m > 0 -> "${m} 分钟"
            else -> "${seconds} 秒"
        }
    }

    private fun decisionLabel(d: String) = when (d) {
        "allow" -> "允许"; "deny" -> "拒绝"; "allow_all" -> "全部允许"; "expired" -> "已过期"; else -> d
    }

    private fun statusLevel(status: String?): String? = when (status?.lowercase()) {
        null, "" -> null
        "ok", "running", "ready", "connected", "active", "success", "completed" -> "ok"
        "error", "failed", "failure" -> "error"
        "disabled", "stopped", "off" -> "off"
        "warn", "warning", "degraded" -> "warn"
        else -> "info"
    }

    private fun toolNames(m: JsonObject): List<String> = (m["tools"] as? JsonArray).orEmpty().mapNotNull { t ->
        when (t) {
            is JsonPrimitive -> t.contentOrNull
            is JsonObject -> t.s("name")
            else -> null
        }
    }

    private fun JsonObject.arr(key: String): List<JsonObject> = (this[key] as? JsonArray).orEmpty().filterIsInstance<JsonObject>()
    private fun JsonObject.s(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString || it.contentOrNull != null && it !is JsonNull }?.contentOrNull?.takeIf { it.isNotBlank() }
    private fun JsonObject.b(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.d(key: String): Double? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
    private fun JsonObject.strings(key: String): List<String> = (this[key] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf { s -> s.isNotBlank() } }
    @Suppress("unused") private fun JsonElement?.orNull() = this
}
