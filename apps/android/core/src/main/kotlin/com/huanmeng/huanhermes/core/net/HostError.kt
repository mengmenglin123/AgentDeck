package com.huanmeng.huanhermes.core.net

/** Errors carry already-redacted messages only. */
sealed class HostError(message: String) : Exception(message) {
    /** Credentials rejected: never retried automatically. */
    class Auth(message: String) : HostError(message)
    class Disconnected(message: String) : HostError(message)
    class Protocol(message: String) : HostError(message)
    class Http(val status: Int, message: String) : HostError(message)
}
