package com.huanmeng.huanhermes.core.net

/** Copyable troubleshooting text; every line goes through [Redactor]. */
object Diagnostics {
    data class Check(val label: String, val ok: Boolean?, val detail: String = "")

    fun checks(bridgeConnected: Boolean, mgmtReachable: Boolean?, hostCapabilities: Set<String>, lastError: String?): List<Check> = listOf(
        Check("Management 接口", mgmtReachable, if (mgmtReachable == false) "无法访问会话列表，检查 IP、端口与 Management 令牌" else ""),
        Check("Bridge 实时连接", bridgeConnected, if (!bridgeConnected) "检查 Bridge 端口与令牌；手机与 Host 需在同一网络或可达" else ""),
        Check(
            "协议 v2（断线续传）",
            if (!bridgeConnected) null else hostCapabilities.contains("resume"),
            if (bridgeConnected && "resume" !in hostCapabilities) "Host companion 版本较旧，建议升级" else "",
        ),
        Check("最近错误", if (lastError.isNullOrBlank()) true else false, lastError.orEmpty()),
    )

    fun report(
        appVersion: String,
        androidSdk: Int,
        config: HostConfig?,
        bridgeState: String,
        hostCapabilities: Set<String>,
        lastError: String?,
    ): String {
        val secrets = config?.secrets.orEmpty()
        val lines = buildList {
            add("HuanHermes $appVersion (Android SDK $androidSdk)")
            if (config != null) {
                add("Host: ${config.urlHost}  Bridge:${config.bridgePort}  Management:${config.mgmtPort}  TLS:${config.useTls}")
                add("Bridge URL: ${config.bridgeWsUrlRedacted}")
            } else add("Host: 未配置")
            add("Bridge 状态: $bridgeState")
            add("Host 能力: ${hostCapabilities.sorted().joinToString(", ").ifEmpty { "（未连接）" }}")
            if (!lastError.isNullOrBlank()) add("最近错误: $lastError")
        }
        return lines.joinToString("\n") { Redactor.redact(it, secrets) }
    }
}
