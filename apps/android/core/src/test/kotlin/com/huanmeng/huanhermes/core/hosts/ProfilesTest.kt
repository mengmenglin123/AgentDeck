package com.huanmeng.huanhermes.core.hosts

import com.huanmeng.huanhermes.core.chat.FakeMgmt
import com.huanmeng.huanhermes.core.mgmt.MgmtApi
import com.huanmeng.huanhermes.core.mgmt.SessionInfo
import com.huanmeng.huanhermes.core.net.HostConfig
import com.huanmeng.huanhermes.core.net.HostError
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ProfilesTest {
    private val cfgA = HostConfig(host = "a.lan", bridgeToken = "ba", mgmtToken = "ma", deviceId = "d")
    private val cfgB = HostConfig(host = "b.lan", bridgeToken = "bb", mgmtToken = "mb", deviceId = "d")

    private class GatedMgmt(val gate: CompletableDeferred<Unit>) : MgmtApi by FakeMgmt() {
        override suspend fun status(): JsonObject { gate.await(); return JsonObject(emptyMap()) }
    }

    @Test fun switchingProfileWhileTestingNeverWritesOldConfigIntoNewProfile() = runTest {
        val storage = MemoryProfileStorage(ProfilesSnapshot(listOf(HostProfile("A", "A", cfgA), HostProfile("B", "B", cfgB)), "A"))
        val gate = CompletableDeferred<Unit>()
        val pm = ProfileManager(storage, { GatedMgmt(gate) })
        pm.load()
        val draftForA = cfgA.copy(host = "a-edited.lan")
        val test = async { pm.testAndSave("A", "A", draftForA) }
        runCurrent()
        assertTrue(pm.state.value.testing)
        pm.select("B")                      // user switches while the probe is in flight
        gate.complete(Unit)
        assertFalse(test.await())
        val s = pm.state.value
        assertEquals("B", s.activeId)
        assertEquals(cfgB, s.profiles.first { it.id == "B" }.config)
        assertEquals(cfgA, s.profiles.first { it.id == "A" }.config) // edit discarded, not saved anywhere
        assertFalse(s.ready)
        assertEquals("b.lan", storage.snapshot.profiles.first { it.id == "B" }.config.host)
    }

    @Test fun successfulTestSavesAndActivates() = runTest {
        val storage = MemoryProfileStorage()
        val pm = ProfileManager(storage, { FakeMgmt() })
        pm.load()
        assertTrue(pm.testAndSave(null, "家里", cfgA))
        assertTrue(pm.state.value.ready)
        assertEquals("家里", storage.snapshot.profiles.single().name)
        assertEquals(storage.snapshot.activeId, storage.snapshot.profiles.single().id)
    }

    @Test fun failedProbeAndInvalidDraftReportErrors() = runTest {
        val pm = ProfileManager(MemoryProfileStorage(), {
            object : MgmtApi by FakeMgmt() { override suspend fun status(): JsonObject = throw HostError.Auth("unauthorized") }
        })
        pm.load()
        assertFalse(pm.testAndSave(null, "x", cfgA))
        assertTrue(pm.state.value.lastError!!.contains("令牌"))
        assertFalse(pm.testAndSave(null, "x", cfgA.copy(bridgePort = 70000)))
        assertTrue(pm.state.value.lastError!!.contains("端口"))
        assertTrue(pm.state.value.profiles.isEmpty())
    }

    private fun session(id: String) = SessionInfo(id, "k$id", "p", id, null, null, false, null, null)

    @Test fun switchingHostClearsSessionsAndDropsStaleResponses() = runTest {
        val gate = CompletableDeferred<Unit>()
        val slowA = object : MgmtApi by FakeMgmt() {
            override suspend fun sessions(project: String?): List<SessionInfo> { gate.await(); return listOf(session("from-A")) }
        }
        val fastB = object : MgmtApi by FakeMgmt() {
            override suspend fun sessions(project: String?) = listOf(session("from-B"))
        }
        val model = SessionsModel()
        model.bind("A", slowA)
        val pending = launch { model.refresh() }
        runCurrent()
        model.bind("B", fastB)
        assertTrue(model.state.value.sessions.isEmpty())
        assertEquals("B", model.state.value.hostId)
        model.refresh()
        gate.complete(Unit); pending.join()
        assertEquals(listOf("from-B"), model.state.value.sessions.map { it.id })
        assertFalse(model.state.value.loading)
    }

    @Test fun closedModelIgnoresResults() = runTest {
        val gate = CompletableDeferred<Unit>()
        val slow = object : MgmtApi by FakeMgmt() {
            override suspend fun sessions(project: String?): List<SessionInfo> { gate.await(); return listOf(session("late")) }
        }
        val model = SessionsModel()
        model.bind("A", slow)
        val pending = launch { model.refresh() }
        runCurrent()
        val before = model.state.value
        model.close()
        gate.complete(Unit); pending.join()
        assertEquals(before, model.state.value)
        assertNull(model.state.value.error)
    }
}
