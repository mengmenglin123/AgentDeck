package com.huanmeng.huanhermes.core.extensions

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** An MCP server the project's Agent loads (GET /mcp). */
data class McpServer(
    val name: String,
    val kind: String,
    val target: String,
    val scope: String,
    val enabled: Boolean,
    val editable: Boolean,
    val tools: List<String>,
    val secretKeys: List<String>,
    val description: String,
)

data class SkillInfo(val id: String, val name: String, val description: String, val scope: String, val path: String?, val editable: Boolean)

data class McpTool(val name: String, val description: String)

/** What a new MCP server needs (POST /mcp). */
data class McpSpec(
    val name: String,
    val kind: String = "stdio",
    val command: String = "",
    val args: List<String> = emptyList(),
    val url: String = "",
    val env: Map<String, String> = emptyMap(),
    val headers: Map<String, String> = emptyMap(),
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("name", name); put("kind", kind)
        if (kind == "stdio") {
            put("command", command)
            put("args", JsonArray(args.map(::JsonPrimitive)))
            if (env.isNotEmpty()) put("env", JsonObject(env.mapValues { JsonPrimitive(it.value) }))
        } else {
            put("url", url)
            if (headers.isNotEmpty()) put("headers", JsonObject(headers.mapValues { JsonPrimitive(it.value) }))
        }
    }

    /** Why it cannot be saved yet, or null. */
    fun problem(): String? = when {
        !Regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$").matches(name) -> "名称只能用字母、数字、_ - ."
        kind == "stdio" && command.isBlank() -> "请填写启动命令"
        kind != "stdio" && !(url.startsWith("https://") || url.startsWith("http://")) -> "地址要以 http(s):// 开头"
        else -> null
    }
}

/** A field the user fills for a connector (a token, a path…). */
data class ConnectorField(val key: String, val label: String, val hint: String = "", val secret: Boolean = false, val placeholder: String = "")

/**
 * A ready-made MCP server ("连接器"). [build] turns the filled fields into a spec;
 * every preset uses the server's own published command or URL.
 */
data class Connector(
    val id: String,
    val title: String,
    val summary: String,
    val category: String,
    val fields: List<ConnectorField> = emptyList(),
    val needs: String? = null,
    val docs: String,
    val build: (Map<String, String>) -> McpSpec,
)

object Extensions {
    private fun JsonObject.s(k: String) = (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonObject.b(k: String) = (this[k] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.strings(k: String) = (this[k] as? JsonArray).orEmpty().mapNotNull {
        (it as? JsonPrimitive)?.content ?: (it as? JsonObject)?.s("name")
    }

    fun parseServers(data: JsonObject): List<McpServer> = (data["servers"] as? JsonArray).orEmpty().mapNotNull { e ->
        val o = e as? JsonObject ?: return@mapNotNull null
        val name = o.s("name") ?: return@mapNotNull null
        McpServer(
            name = name, kind = o.s("kind") ?: "stdio", target = o.s("target").orEmpty(),
            scope = o.s("scope") ?: "host", enabled = o.b("enabled") != false, editable = o.b("editable") == true,
            tools = o.strings("tools"), secretKeys = o.strings("secret_keys"), description = o.s("description").orEmpty(),
        )
    }

    fun parseSkills(data: JsonObject): List<SkillInfo> = (data["skills"] as? JsonArray).orEmpty().mapNotNull { e ->
        val o = e as? JsonObject ?: return@mapNotNull null
        val name = o.s("name") ?: return@mapNotNull null
        SkillInfo(o.s("id") ?: name, name, o.s("description").orEmpty(), o.s("scope") ?: o.s("source") ?: "host", o.s("path"), o.b("editable") == true)
    }

    fun parseTools(data: JsonObject): List<McpTool> = (data["tools"] as? JsonArray).orEmpty().mapNotNull { e ->
        val o = e as? JsonObject ?: return@mapNotNull null
        McpTool(o.s("name") ?: return@mapNotNull null, o.s("description").orEmpty())
    }

    fun skillBody(name: String, description: String, body: String): JsonObject = buildJsonObject {
        put("name", name.trim()); put("description", description.trim()); put("body", body)
    }

    fun skillNameProblem(name: String): String? =
        if (Regex("^[a-z0-9][a-z0-9-]{0,63}$").matches(name)) null else "名称用小写字母、数字和 -，例如 deploy-check"

    /** `KEY=VALUE` lines → map (blank and malformed lines ignored). */
    fun parsePairs(text: String): Map<String, String> = text.lines().mapNotNull { line ->
        val i = line.indexOf('=')
        if (i <= 0) null else line.substring(0, i).trim().takeIf { it.isNotEmpty() }?.let { it to line.substring(i + 1).trim() }
    }.toMap()

    /** A command line → command + args (quotes keep spaces together). */
    fun splitCommand(line: String): Pair<String, List<String>> {
        val parts = Regex("\"([^\"]*)\"|'([^']*)'|(\\S+)").findAll(line).map { m ->
            m.groups[1]?.value ?: m.groups[2]?.value ?: m.value
        }.toList()
        return (parts.firstOrNull().orEmpty()) to parts.drop(1)
    }

    private fun stdio(name: String, command: String, vararg args: String, env: Map<String, String> = emptyMap()) =
        McpSpec(name, "stdio", command, args.toList(), env = env.filterValues { it.isNotBlank() })
    private fun http(name: String, url: String, headers: Map<String, String> = emptyMap()) =
        McpSpec(name, "http", url = url, headers = headers.filterValues { it.isNotBlank() })

    val connectors: List<Connector> = listOf(
        Connector("github", "GitHub", "仓库、Issue、PR、Actions", "开发",
            listOf(ConnectorField("token", "GitHub Token", "fine-grained PAT，按需勾选权限", secret = true, placeholder = "github_pat_…")),
            docs = "https://github.com/github/github-mcp-server",
            build = { f -> http("github", "https://api.githubcopilot.com/mcp/", mapOf("Authorization" to "Bearer ${f["token"].orEmpty()}")) }),
        Connector("playwright", "Playwright 浏览器", "打开网页、点击、截图、测前端", "开发", needs = "Host 需要 Node.js",
            docs = "https://github.com/microsoft/playwright-mcp",
            build = { stdio("playwright", "npx", "-y", "@playwright/mcp@latest") }),
        Connector("context7", "Context7 文档", "查最新的库文档和示例", "开发", needs = "Host 需要 Node.js",
            docs = "https://github.com/upstash/context7",
            build = { stdio("context7", "npx", "-y", "@upstash/context7-mcp") }),
        Connector("filesystem", "文件系统", "读写指定目录", "本机",
            listOf(ConnectorField("dir", "允许访问的目录", "Host 上的绝对路径", placeholder = "/home/me/docs")), needs = "Host 需要 Node.js",
            docs = "https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem",
            build = { f -> stdio("filesystem", "npx", "-y", "@modelcontextprotocol/server-filesystem", f["dir"].orEmpty()) }),
        Connector("fetch", "网页抓取", "把网页转成 Markdown 给 Agent 读", "本机", needs = "Host 需要 uv（uvx）",
            docs = "https://github.com/modelcontextprotocol/servers/tree/main/src/fetch",
            build = { stdio("fetch", "uvx", "mcp-server-fetch") }),
        Connector("memory", "知识图谱记忆", "跨会话记住实体和关系", "本机", needs = "Host 需要 Node.js",
            docs = "https://github.com/modelcontextprotocol/servers/tree/main/src/memory",
            build = { stdio("memory", "npx", "-y", "@modelcontextprotocol/server-memory") }),
        Connector("sequential-thinking", "分步思考", "把复杂问题拆成步骤推理", "本机", needs = "Host 需要 Node.js",
            docs = "https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking",
            build = { stdio("sequential-thinking", "npx", "-y", "@modelcontextprotocol/server-sequential-thinking") }),
        Connector("notion", "Notion", "页面和数据库（OAuth 登录）", "办公", needs = "首次使用要在 Agent 里完成 OAuth 登录",
            docs = "https://developers.notion.com/docs/mcp",
            build = { http("notion", "https://mcp.notion.com/mcp") }),
        Connector("linear", "Linear", "Issue 和项目（OAuth 登录）", "办公", needs = "首次使用要在 Agent 里完成 OAuth 登录",
            docs = "https://linear.app/docs/mcp",
            build = { http("linear", "https://mcp.linear.app/mcp") }),
        Connector("sentry", "Sentry", "错误和性能问题（OAuth 登录）", "运维", needs = "首次使用要在 Agent 里完成 OAuth 登录",
            docs = "https://docs.sentry.io/product/sentry-mcp/",
            build = { http("sentry", "https://mcp.sentry.dev/mcp") }),
    )

    fun connector(id: String): Connector? = connectors.firstOrNull { it.id == id }
}
