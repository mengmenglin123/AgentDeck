package com.huanmeng.huanhermes.core.protocol

import com.fasterxml.jackson.databind.ObjectMapper
import com.networknt.schema.JsonSchemaFactory
import com.networknt.schema.SpecVersion
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Contract tests against the single-source schema in docs/protocol/schema:
 * every Host sample parses into its typed frame, unknown types degrade to
 * placeholders, and every frame this app sends validates against the schema.
 */
class ContractTest {
    private val dir = File(System.getProperty("huanhermes.protocolDir") ?: "../../../docs/protocol", "schema")
    private val schemaText = File(dir, "bridge.v2.schema.json").readText()
    private val samples = ProtocolJson.parseToJsonElement(File(dir, "samples/bridge-samples.json").readText()).jsonObject
    private val mapper = ObjectMapper()
    private val schemaNode = mapper.readTree(schemaText)
    private val factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012)

    private fun validate(direction: String, frame: JsonObject): Set<String> {
        val type = (frame["type"] as kotlinx.serialization.json.JsonPrimitive).content
        val def = schemaNode["\$defs"][direction][type] ?: return setOf("unknown $direction type $type")
        val schema = factory.getSchema(def)
        return schema.validate(mapper.readTree(frame.toString())).map { it.message }.toSet()
    }

    private fun list(key: String) = (samples[key] as JsonArray).map { it.jsonObject }

    @Test fun everyHostSampleParsesToItsTypedFrame() {
        for (frame in list("host_to_app")) {
            val parsed = BridgeFrame.from(frame)
            assertFalse("${frame["type"]} parsed as Unknown", parsed is BridgeFrame.Unknown)
            assertTrue(validate("host_to_app", frame).isEmpty())
        }
    }

    @Test fun unknownTypesBecomePlaceholders() {
        for (frame in list("host_to_app_unknown")) {
            val parsed = BridgeFrame.from(frame)
            assertTrue(parsed is BridgeFrame.Unknown)
            assertEquals("huan:dev:c1", parsed.sessionKey)
        }
        assertEquals(null, BridgeFrame.parse("[1,2]"))
        assertEquals(null, BridgeFrame.parse("{oops"))
    }

    @Test fun v2FieldsAreReadAndOptional() {
        val ack = BridgeFrame.from(list("host_to_app")[1]) as BridgeFrame.RegisterAck
        assertEquals(2, ack.protocol)
        assertEquals(setOf("seq", "resume", "session_status"), ack.capabilities)
        val legacy = BridgeFrame.from(list("host_to_app")[0]) as BridgeFrame.RegisterAck
        assertEquals(1, legacy.protocol)
        assertTrue(legacy.ok && !legacy.isFailure())
        val stream = list("host_to_app").first { it.toString().contains("\"replayed\":true") }
        assertTrue(BridgeFrame.from(stream).replayed)
        val tool = BridgeFrame.from(list("host_to_app").first { it.toString().contains("\"tool_call\"") }) as BridgeFrame.ToolCall
        assertEquals("call-1", tool.callId)
        val card = BridgeFrame.from(list("host_to_app").first { it.toString().contains("perm:p1:allow") }) as BridgeFrame.Card
        assertEquals(listOf("perm:p1:allow", "perm:p1:allow_all", "perm:p1:deny"), card.buttons.map { it.data })
    }

    @Test fun everyOutboundFrameValidates() {
        val frames = listOf(
            Outbound.register("huanhermes-android", "dev", "0.2.1"),
            Outbound.message("huan:dev:c1", "你好", "codex"),
            Outbound.message("huan:dev:c1", "x", null),
            Outbound.cancel("huan:dev:c1", null, "codex"),
            Outbound.cardAction("huan:dev:c1", "perm:p1:allow_all", "ctx-1", null),
            Outbound.ping(1L),
            Outbound.previewAck("r", "h"),
            Outbound.resume("huan:dev:c1", 0, "e"),
            Outbound.resume("huan:dev:c1", 7, null),
            Outbound.sessionStatus("huan:dev:c1"),
        )
        for (f in frames) assertEquals(f.toString(), emptySet<String>(), validate("app_to_host", f))
        for (f in list("app_to_host")) assertEquals(f.toString(), emptySet<String>(), validate("app_to_host", f))
    }

    @Test fun schemaRejectsBadFrames() {
        val bad = ProtocolJson.parseToJsonElement("""{"type":"resume","session_key":"s","after_seq":-1}""").jsonObject
        assertTrue(validate("app_to_host", bad).isNotEmpty())
    }

    @Test fun permissionDecisionResolvesToExactButtonData() {
        val buttons = listOf(FrameButton("Allow", "perm:p9:allow"), FrameButton("Allow all", "perm:p9:allow_all"), FrameButton("Deny", "perm:p9:deny"))
        assertEquals("perm:p9:deny", Outbound.resolvePermissionAction("deny", buttons))
        assertEquals("perm:p9:allow", Outbound.resolvePermissionAction("allow", buttons))
        assertEquals("perm:p9:allow_all", Outbound.resolvePermissionAction("allow_all", buttons))
        assertEquals("perm:x:deny", Outbound.resolvePermissionAction("perm:x:deny", buttons))
    }
}
