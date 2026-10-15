package com.huanmeng.huanhermes

import org.junit.Assert.assertTrue
import org.junit.Test

class VersionTest {
    @Test
    fun versionCodeOutranksFlutterBuilds() {
        // Flutter builds use versionCode 2xx; native must stay higher to install over them.
        assertTrue(BuildConfig.VERSION_CODE >= 2000)
    }
}
