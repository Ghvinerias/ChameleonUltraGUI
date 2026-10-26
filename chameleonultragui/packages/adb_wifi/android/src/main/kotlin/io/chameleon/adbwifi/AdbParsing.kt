package io.chameleon.adbwifi

/** Error codes sent over the method channel; mirrored by `AdbWifiErrorType` in Dart. */
object AdbErrorCode {
    const val SIGNATURE_MISMATCH = "signature_mismatch"
    const val NO_MATCHING_ABIS = "no_matching_abis"
    const val CONNECTION_FAILED = "connection_failed"
    const val PAIRING_FAILED = "pairing_failed"
    const val NOT_CONNECTED = "not_connected"
    const val OTHER = "other"
}

/** Pure parsing helpers (no Android/Kadb dependency, unit tested on the JVM). */
object AdbParsing {
    /** Maps the text of a failed `pm/cmd package install` to an [AdbErrorCode]. */
    fun classifyInstallFailure(message: String?): String {
        val m = message ?: return AdbErrorCode.OTHER
        return when {
            m.contains("INSTALL_FAILED_UPDATE_INCOMPATIBLE") ||
                m.contains("INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES") -> AdbErrorCode.SIGNATURE_MISMATCH
            m.contains("INSTALL_FAILED_NO_MATCHING_ABIS") -> AdbErrorCode.NO_MATCHING_ABIS
            else -> AdbErrorCode.OTHER
        }
    }

    /**
     * Classifies a connection-time throwable by class name and message, so it also works for
     * library exception types we do not want to reference here.
     */
    fun classifyConnectFailure(className: String, message: String?): String {
        val text = "$className ${message ?: ""}".lowercase()
        return when {
            "auth" in text || "pairing required" in text || "need adb authority" in text -> AdbErrorCode.PAIRING_FAILED
            else -> AdbErrorCode.CONNECTION_FAILED
        }
    }

    data class PackageVersion(val versionName: String?, val versionCode: Long?)

    /** Extracts versionName/versionCode of the package from `dumpsys package <pkg>` output. */
    fun parsePackageVersion(dumpsys: String): PackageVersion? {
        val name = Regex("""versionName=(\S+)""").find(dumpsys)?.groupValues?.get(1)
        val code = Regex("""versionCode=(\d+)""").find(dumpsys)?.groupValues?.get(1)?.toLongOrNull()
        if (name == null && code == null) return null
        return PackageVersion(name, code)
    }

    /** Last non-empty line of `cmd package resolve-activity --brief` output, i.e. `pkg/.Activity`. */
    fun parseResolvedActivity(output: String): String? =
        output.lines().map { it.trim() }.lastOrNull { it.contains('/') && !it.contains(' ') }

    /** Validates a user supplied host (IPv4 literal or hostname) and port range. */
    fun isValidEndpoint(host: String, port: Int): Boolean =
        host.isNotBlank() && host.all { it.isLetterOrDigit() || it == '.' || it == '-' || it == ':' } && port in 1..65535
}
