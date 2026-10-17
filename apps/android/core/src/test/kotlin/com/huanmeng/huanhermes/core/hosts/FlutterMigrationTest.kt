package com.huanmeng.huanhermes.core.hosts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FlutterMigrationTest {
    @Test fun importsProfilesTokensAndDeviceId() {
        val json = """[{"id":"a","name":"Home","updatedAt":"2026-01-01","config":{"host":"10.0.0.2","bridgePort":9810,"mgmtPort":9820,"useTls":false,"platformName":"huanhermes-app","deviceId":"dev123"}},
            {"id":"b","name":" ","config":{"host":"box","bridgePort":70000,"useTls":true}},{"id":"","config":{"host":"x"}},{"name":"nohost","id":"c","config":{}}]"""
        val secrets = mapOf(FlutterMigration.bridgeKey("a") to "bt", FlutterMigration.mgmtKey("a") to "mt")
        val snap = FlutterMigration.parse(json, "b", secrets::get)!!
        assertEquals(listOf("a", "b"), snap.profiles.map { it.id })
        assertEquals("b", snap.activeId)
        val a = snap.profiles[0]
        assertEquals("dev123", a.config.deviceId); assertEquals("bt", a.config.bridgeToken); assertEquals("mt", a.config.mgmtToken)
        assertEquals("Host", snap.profiles[1].name)
        assertEquals(9810, snap.profiles[1].config.bridgePort)
        assertEquals(true, snap.profiles[1].config.useTls)
        assertEquals("a", FlutterMigration.parse(json, "zzz", secrets::get)!!.activeId)
        assertNull(FlutterMigration.parse("not json", null) { null })
        assertNull(FlutterMigration.parse(null, null) { null })
        assertNull(FlutterMigration.parse("[]", null) { null })
    }
}
