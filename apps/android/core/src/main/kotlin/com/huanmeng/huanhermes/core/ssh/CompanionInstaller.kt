package com.huanmeng.huanhermes.core.ssh

import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.protocol.ProtocolJson
import com.trilead.ssh2.Connection
import com.trilead.ssh2.SCPClient
import com.trilead.ssh2.ServerHostKeyVerifier
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

data class SshTarget(
    val host: String,
    val port: Int = 22,
    val username: String,
    val password: String? = null,
    val privateKeyPem: String? = null,
    val passphrase: String? = null,
)

data class ExecResult(val exitCode: Int?, val stdout: String, val stderr: String)

/** What an SSH session must offer; real one is sshlib, tests use a fake. */
interface SshRunner : AutoCloseable {
    fun run(command: String, timeoutMs: Long = 120_000): ExecResult
    fun upload(bytes: ByteArray, remoteDir: String, remoteName: String)
}

class SshException(message: String) : Exception(message)

/** OpenSSH-style `SHA256:…` fingerprint of a host key blob. */
fun sshFingerprint(keyBlob: ByteArray): String =
    "SHA256:" + Base64.getEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(keyBlob))

/**
 * sshlib (ConnectBot, Apache-2.0) session. [verifyHostKey] gets the key type
 * and fingerprint and must return true to continue (trust-on-first-use).
 */
class TrileadSshRunner(target: SshTarget, verifyHostKey: (String, String) -> Boolean, connectTimeoutMs: Int = 15_000) : SshRunner {
    private val conn = Connection(target.host.trim(), target.port)

    init {
        try {
            conn.connect(ServerHostKeyVerifier { _, _, algorithm, key -> verifyHostKey(algorithm, sshFingerprint(key)) }, connectTimeoutMs, connectTimeoutMs)
        } catch (e: Exception) {
            conn.close()
            val msg = e.message.orEmpty()
            throw SshException(if (msg.contains("verif", true) || msg.contains("host key", true)) "SSH 主机指纹未被确认，已中止连接" else "SSH 连接失败：${e.message ?: e.javaClass.simpleName}")
        }
        val ok = try {
            when {
                !target.privateKeyPem.isNullOrBlank() -> conn.authenticateWithPublicKey(target.username, target.privateKeyPem.toCharArray(), target.passphrase)
                !target.password.isNullOrEmpty() -> conn.authenticateWithPassword(target.username, target.password)
                else -> false
            }
        } catch (e: Exception) {
            conn.close(); throw SshException("SSH 认证失败：${e.message}")
        }
        if (!ok) { conn.close(); throw SshException("SSH 认证失败：用户名、密码或私钥不正确") }
    }

    override fun run(command: String, timeoutMs: Long): ExecResult {
        val s = conn.openSession()
        try {
            s.execCommand(asciiCommand(command))
            val out = ByteArrayOutputStream(); val err = ByteArrayOutputStream()
            val deadline = System.currentTimeMillis() + timeoutMs
            val so = s.stdout; val se = s.stderr
            val buf = ByteArray(8192)
            while (true) {
                var progressed = false
                while (so.available() > 0) { val n = so.read(buf); if (n > 0) { out.write(buf, 0, n); progressed = true } }
                while (se.available() > 0) { val n = se.read(buf); if (n > 0) { err.write(buf, 0, n); progressed = true } }
                val cond = s.waitForCondition(com.trilead.ssh2.ChannelCondition.STDOUT_DATA or com.trilead.ssh2.ChannelCondition.STDERR_DATA or com.trilead.ssh2.ChannelCondition.EOF or com.trilead.ssh2.ChannelCondition.EXIT_STATUS, 500)
                if (cond and com.trilead.ssh2.ChannelCondition.EOF != 0 && so.available() == 0 && se.available() == 0 && !progressed) break
                if (System.currentTimeMillis() > deadline) throw SshException("远端命令超时")
            }
            s.waitForCondition(com.trilead.ssh2.ChannelCondition.EXIT_STATUS, 5_000)
            return ExecResult(s.exitStatus, out.toString(Charsets.UTF_8), err.toString(Charsets.UTF_8))
        } finally {
            s.close()
        }
    }

    override fun upload(bytes: ByteArray, remoteDir: String, remoteName: String) {
        SCPClient(conn).put(bytes, remoteName, remoteDir, "0600")
    }

    override fun close() = conn.close()

    companion object {
        fun shellQuote(s: String) = "'" + s.replace("'", "'\\''") + "'"

        /**
         * sshlib sends the exec string in a single-byte charset, which mangles
         * non-ASCII text (Chinese paths, messages). Non-ASCII commands travel as
         * POSIX printf octal escapes and are rebuilt as UTF-8 bytes on the server.
         */
        fun asciiCommand(command: String): String {
            if (command.all { it.code in 1..126 }) return "sh -c " + shellQuote(command)
            val esc = StringBuilder()
            for (b in command.toByteArray(Charsets.UTF_8)) {
                val c = b.toInt() and 0xff
                if (c in 0x20..0x7e && c.toChar() !in "'\"\\$`%") esc.append(c.toChar())
                else esc.append('\\').append(Integer.toOctalString(c).padStart(3, '0'))
            }
            // Trailing x keeps $(...) from eating final newlines; ${c%x} strips it again.
            return "sh -c 'c=$(printf \"" + esc + "x\"); eval \"$" + "{c%x}\"'"
        }
    }
}

data class CompanionBundle(val version: String, val sha256: String, val bytes: ByteArray) {
    fun verify(): Boolean = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) } == sha256.lowercase()
}

data class CompanionResult(val config: HostConfig, val version: String, val serviceStarted: Boolean)

/** Installs the bundled Host companion over SSH and returns a ready HostConfig (mirrors the Flutter flow). */
object CompanionInstaller {
    private val remotePathRe = Regex("^/tmp/huanhermes-companion-[a-f0-9]{32}\\.tar\\.gz$")
    private val versionRe = Regex("^[0-9]+\\.[0-9]+\\.[0-9]+$")
    private val shaRe = Regex("^[a-f0-9]{64}$")

    fun remoteArchive(random: SecureRandom = SecureRandom()): String {
        val b = ByteArray(16).also(random::nextBytes)
        return "/tmp/huanhermes-companion-" + b.joinToString("") { "%02x".format(it) } + ".tar.gz"
    }

    fun installCommand(archive: String, sha256: String, version: String): String {
        require(remotePathRe.matches(archive)) { "远端安装包路径无效" }
        require(shaRe.matches(sha256)) { "安装包校验值无效" }
        require(versionRe.matches(version)) { "版本号无效" }
        return """set -eu
umask 077
archive='$archive'
work="${'$'}{archive%.tar.gz}"
trap 'rm -rf -- "${'$'}work" "${'$'}archive"' EXIT HUP INT TERM
command -v python3 >/dev/null 2>&1 || { echo "需要 python3" >&2; exit 3; }
command -v tar >/dev/null 2>&1 || { echo "需要 tar" >&2; exit 3; }
command -v sha256sum >/dev/null 2>&1 || { echo "需要 sha256sum" >&2; exit 3; }
printf '%s  %s\n' '$sha256' "${'$'}archive" | sha256sum -c - >/dev/null
rm -rf -- "${'$'}work"
mkdir -p -- "${'$'}work"
tar -xzf "${'$'}archive" -C "${'$'}work" --strip-components=1
python3 "${'$'}work/server/companion_installer.py" install --source "${'$'}work" --prefix "${'$'}HOME/.local/share/huanhermes" --version '$version'
"""
    }

    fun configureCommand(lan: Boolean): String =
        "set -eu\npython3 \"\$HOME/.local/share/huanhermes/current/server/companion_configurator.py\" --prefix \"\$HOME/.local/share/huanhermes\" --workspace \"\$HOME\" --start" +
            if (lan) " --bind 0.0.0.0" else ""

    private fun tagged(output: String, tag: String): JsonObject? = output.lineSequence()
        .filter { it.startsWith("$tag\t") }
        .mapNotNull { runCatching { ProtocolJson.parseToJsonElement(it.substringAfter('\t')).jsonObject }.getOrNull() }
        .lastOrNull()

    fun parseInstall(output: String): Pair<String, Boolean> {
        val o = tagged(output, "HH_COMPANION") ?: throw SshException("服务器未返回有效的 Companion 安装结果")
        val version = (o["version"] as? JsonPrimitive)?.contentOrNull ?: throw SshException("安装结果缺少版本")
        return version to ((o["service_started"] as? JsonPrimitive)?.booleanOrNull == true)
    }

    fun parseConfig(output: String, host: String): HostConfig {
        val o = tagged(output, "HH_COMPANION_CONFIG") ?: throw SshException("服务器未返回有效的 Host 配置")
        fun s(k: String) = (o[k] as? JsonPrimitive)?.contentOrNull.orEmpty()
        fun i(k: String) = (o[k] as? JsonPrimitive)?.intOrNull
        val bt = s("bridge_token"); val mt = s("mgmt_token")
        val bp = i("bridge_port"); val mp = i("mgmt_port")
        if (bt.isEmpty() || mt.isEmpty() || bp == null || mp == null) throw SshException("Host 配置不完整")
        return HostConfig(host = host, bridgePort = bp, mgmtPort = mp, bridgeToken = bt, mgmtToken = mt)
    }

    suspend fun install(
        target: SshTarget,
        bundle: CompanionBundle,
        connect: (SshTarget) -> SshRunner,
        progress: (String) -> Unit = {},
        lan: Boolean = true,
    ): CompanionResult = withContext(Dispatchers.IO) {
        if (target.host.isBlank() || target.username.isBlank()) throw SshException("SSH 主机和用户名不能为空")
        if (target.password.isNullOrEmpty() && target.privateKeyPem.isNullOrBlank()) throw SshException("请输入 SSH 密码或私钥")
        if (!bundle.verify()) throw SshException("内置安装包校验失败")
        progress("正在连接 ${target.host}…")
        connect(target).use { ssh ->
            val archive = remoteArchive()
            progress("正在上传 Host companion ${bundle.version}…")
            ssh.upload(bundle.bytes, "/tmp", archive.substringAfterLast('/'))
            progress("正在安装…")
            val inst = ssh.run("printf 'HH_COMPANION_TRANSPORT\\tSCP\\n'\n" + installCommand(archive, bundle.sha256, bundle.version))
            if (inst.exitCode != 0) throw SshException("Companion 安装失败" + inst.stderr.trim().takeIf { it.isNotEmpty() }?.let { "：${it.take(300)}" }.orEmpty())
            val (version, started) = parseInstall(inst.stdout)
            progress("正在生成 Host 配置…")
            val cfg = ssh.run(configureCommand(lan), 60_000)
            if (cfg.exitCode != 0) throw SshException("Host 配置初始化失败" + cfg.stderr.trim().takeIf { it.isNotEmpty() }?.let { "：${it.take(300)}" }.orEmpty())
            val serviceStarted = started || cfg.stdout.contains("\"service_started\":true")
            CompanionResult(parseConfig(cfg.stdout, target.host.trim()), version, serviceStarted)
        }
    }
}
