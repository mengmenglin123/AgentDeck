package com.huanmeng.huanhermes.ui.pairing

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** A Host advertising `_huanhermes._tcp` on the LAN (ports and TLS only, never tokens). */
data class FoundHost(val name: String, val host: String, val bridgePort: Int, val mgmtPort: Int, val tls: Boolean)

/** NsdManager discovery; resolves one service at a time (pre-Android 14 limit). */
class HostDiscovery(context: Context) {
    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val _found = MutableStateFlow<List<FoundHost>>(emptyList())
    val found: StateFlow<List<FoundHost>> = _found.asStateFlow()
    private val _searching = MutableStateFlow(false)
    val searching: StateFlow<Boolean> = _searching.asStateFlow()
    private val queue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var listener: NsdManager.DiscoveryListener? = null

    fun start() {
        val m = nsd ?: return
        if (listener != null) return
        val l = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) { _searching.value = true }
            override fun onDiscoveryStopped(serviceType: String) { _searching.value = false }
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) { _searching.value = false; listener = null }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceFound(info: NsdServiceInfo) { synchronized(queue) { queue.addLast(info) }; next() }
            override fun onServiceLost(info: NsdServiceInfo) { _found.update { list -> list.filterNot { it.name == info.serviceName } } }
        }
        listener = l
        runCatching { m.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, l) }.onFailure { listener = null }
    }

    @Suppress("DEPRECATION")
    private fun next() {
        val m = nsd ?: return
        val info = synchronized(queue) {
            if (resolving) return
            queue.removeFirstOrNull()?.also { resolving = true }
        } ?: return
        runCatching {
            m.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) { done() }
                override fun onServiceResolved(s: NsdServiceInfo) {
                    val attrs = s.attributes.mapValues { (_, v) -> v?.toString(Charsets.UTF_8).orEmpty() }
                    val host = s.host?.hostAddress?.substringBefore('%')
                    if (host != null) {
                        val f = FoundHost(
                            name = s.serviceName, host = host,
                            bridgePort = attrs["bridge"]?.toIntOrNull() ?: s.port,
                            mgmtPort = attrs["mgmt"]?.toIntOrNull() ?: 9820,
                            tls = attrs["tls"] == "1",
                        )
                        _found.update { list -> (list.filterNot { it.name == f.name } + f).sortedBy { it.name } }
                    }
                    done()
                }
            })
        }.onFailure { done() }
    }

    private fun done() {
        synchronized(queue) { resolving = false }
        next()
    }

    fun stop() {
        val l = listener ?: return
        listener = null
        runCatching { nsd?.stopServiceDiscovery(l) }
        _searching.value = false
    }

    companion object { const val TYPE = "_huanhermes._tcp." }
}
