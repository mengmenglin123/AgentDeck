package com.huanmeng.huanhermes.core.net

import okhttp3.OkHttpClient
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.Base64
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * Certificate pinning for Hosts behind TLS. A pinned Host is trusted when its
 * leaf public key matches the pin, even with a self-signed certificate; an
 * unpinned TLS Host uses the normal system trust store.
 */
object Pinning {
    fun normalize(raw: String): String = raw.trim().removePrefix("sha256/").trim()

    fun spkiSha256(cert: X509Certificate): String =
        Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-256").digest(cert.publicKey.encoded))

    class PinnedTrustManager(private val pin: String) : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = throw CertificateException("client auth unsupported")
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
            val leaf = chain?.firstOrNull() ?: throw CertificateException("empty chain")
            if (spkiSha256(leaf) != pin) throw CertificateException("certificate pin mismatch")
            leaf.checkValidity()
        }
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    /** A client for [config]: pinned when it has a pin, otherwise [base] unchanged. */
    fun clientFor(base: OkHttpClient, config: HostConfig): OkHttpClient {
        val pin = normalize(config.certPin)
        if (!config.useTls || pin.isEmpty()) return base
        val tm = PinnedTrustManager(pin)
        val ctx = SSLContext.getInstance("TLS").apply { init(null, arrayOf(tm), null) }
        // The pin is the identity; the certificate's names may be an IP or self-chosen.
        val verifier = HostnameVerifier { _, session ->
            (session.peerCertificates.firstOrNull() as? X509Certificate)?.let { spkiSha256(it) == pin } == true
        }
        return base.newBuilder().sslSocketFactory(ctx.socketFactory, tm).hostnameVerifier(verifier).build()
    }

    @Suppress("unused")
    internal fun systemTrustManager(): X509TrustManager =
        TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(null as KeyStore?) }
            .trustManagers.filterIsInstance<X509TrustManager>().first()
}
