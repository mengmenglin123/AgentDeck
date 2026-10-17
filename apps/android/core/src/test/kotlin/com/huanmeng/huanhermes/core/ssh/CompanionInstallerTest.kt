package com.huanmeng.huanhermes.core.ssh

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.security.MessageDigest

class CompanionInstallerTest {
    private val bytes = "fake-tarball".toByteArray()
    private val sha = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private class FakeSsh(val results: ArrayDeque<ExecResult>) : SshRunner {
        val commands = mutableListOf<String>()
        var uploaded: Pair<String, String>? = null
        var closed = false
        override fun run(command: String, timeoutMs: Long): ExecResult { commands += command; return results.removeFirst() }
        override fun upload(bytes: ByteArray, remoteDir: String, remoteName: String) { uploaded = remoteDir to remoteName }
        override fun close() { closed = true }
    }

    @Test fun installUploadsVerifiesAndReturnsConfig() = runBlocking {
        val ssh = FakeSsh(ArrayDeque(listOf(
            ExecResult(0, "HH_COMPANION_TRANSPORT\tSCP\nHH_COMPANION\t{\"version\":\"0.2.7\",\"service_started\":true}\n", ""),
            ExecResult(0, "HH_COMPANION_CONFIG\t{\"bridge_token\":\"bt\",\"mgmt_token\":\"mt\",\"bridge_port\":9810,\"mgmt_port\":9820,\"config_path\":\"/x\"}\n", ""),
        )))
        val steps = mutableListOf<String>()
        val r = CompanionInstaller.install(SshTarget("10.0.0.9", 22, "me", password = "pw"), CompanionBundle("0.2.7", sha, bytes), { ssh }, steps::add)
        assertEquals("10.0.0.9", r.config.host); assertEquals("bt", r.config.bridgeToken); assertEquals(9820, r.config.mgmtPort)
        assertTrue(r.serviceStarted)
        assertEquals("/tmp", ssh.uploaded!!.first)
        assertTrue(Regex("huanhermes-companion-[a-f0-9]{32}\\.tar\\.gz").matches(ssh.uploaded!!.second))
        assertTrue(ssh.commands[0].contains(sha)); assertTrue(ssh.commands[0].contains("sha256sum -c"))
        assertTrue(ssh.closed)
        assertTrue(ssh.commands[1].contains("--bind 0.0.0.0")); assertTrue(ssh.commands[1].contains("--start"))
        assertEquals(4, steps.size)
    }

    @Test fun failuresAreReadable() = runBlocking {
        val bad = CompanionBundle("0.2.7", "0".repeat(64), bytes)
        try { CompanionInstaller.install(SshTarget("h", 22, "u", password = "p"), bad, { error("no") }); fail() } catch (e: SshException) { assertTrue(e.message!!.contains("校验")) }
        try { CompanionInstaller.install(SshTarget("h", 22, "u"), CompanionBundle("0.2.7", sha, bytes), { error("no") }); fail() } catch (e: SshException) { assertTrue(e.message!!.contains("密码")) }
        val ssh = FakeSsh(ArrayDeque(listOf(ExecResult(3, "", "需要 python3"))))
        try { CompanionInstaller.install(SshTarget("h", 22, "u", password = "p"), CompanionBundle("0.2.7", sha, bytes), { ssh }); fail() } catch (e: SshException) { assertTrue(e.message!!.contains("python3")) }
    }

    @Test fun commandGuards() {
        try { CompanionInstaller.installCommand("/tmp/evil;rm -rf ~", "a".repeat(64), "0.2.7"); fail() } catch (_: IllegalArgumentException) {}
        try { CompanionInstaller.installCommand(CompanionInstaller.remoteArchive(), "a".repeat(64), "1.0'x"); fail() } catch (_: IllegalArgumentException) {}
        assertEquals("'it'\\''s'", TrileadSshRunner.shellQuote("it's"))
        assertTrue(sshFingerprint(byteArrayOf(1, 2, 3)).startsWith("SHA256:"))
    }
}
