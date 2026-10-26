package io.chameleon.adbwifi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AdbParsingTest {
    @Test
    fun classifiesInstallFailures() {
        assertEquals(
            AdbErrorCode.SIGNATURE_MISMATCH,
            AdbParsing.classifyInstallFailure(
                "Install failed: Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package io.chameleon.ultra signatures do not match]"
            )
        )
        assertEquals(
            AdbErrorCode.SIGNATURE_MISMATCH,
            AdbParsing.classifyInstallFailure("Failure [INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES]")
        )
        assertEquals(
            AdbErrorCode.NO_MATCHING_ABIS,
            AdbParsing.classifyInstallFailure("Failure [INSTALL_FAILED_NO_MATCHING_ABIS: Failed to extract native libraries, res=-113]")
        )
        assertEquals(AdbErrorCode.OTHER, AdbParsing.classifyInstallFailure("Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]"))
        assertEquals(AdbErrorCode.OTHER, AdbParsing.classifyInstallFailure(null))
    }

    @Test
    fun classifiesConnectFailures() {
        assertEquals(
            AdbErrorCode.CONNECTION_FAILED,
            AdbParsing.classifyConnectFailure("java.net.ConnectException", "Connection refused")
        )
        assertEquals(
            AdbErrorCode.CONNECTION_FAILED,
            AdbParsing.classifyConnectFailure("java.net.SocketTimeoutException", "timeout")
        )
        assertEquals(
            AdbErrorCode.PAIRING_FAILED,
            AdbParsing.classifyConnectFailure("com.flyfishxu.kadb.exception.AdbAuthException", "Need adb authority")
        )
        assertEquals(
            AdbErrorCode.PAIRING_FAILED,
            AdbParsing.classifyConnectFailure("com.flyfishxu.kadb.exception.AdbPairAuthException", "Pairing required or trust missing")
        )
    }

    @Test
    fun parsesPackageVersion() {
        val out = """
            Packages:
              Package [io.chameleon.ultra] (abc):
                versionCode=123 minSdk=24 targetSdk=36
                versionName=1.2.3-dev
        """.trimIndent()
        val v = AdbParsing.parsePackageVersion(out)!!
        assertEquals("1.2.3-dev", v.versionName)
        assertEquals(123L, v.versionCode)
        assertNull(AdbParsing.parsePackageVersion("Unable to find package: io.chameleon.ultra"))
    }

    @Test
    fun parsesResolvedActivity() {
        val out = "priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true\nio.chameleon.ultra/.MainActivity\n"
        assertEquals("io.chameleon.ultra/.MainActivity", AdbParsing.parseResolvedActivity(out))
        assertNull(AdbParsing.parseResolvedActivity("No activity found"))
    }

    @Test
    fun validatesEndpoint() {
        assertTrue(AdbParsing.isValidEndpoint("192.168.1.20", 37625))
        assertFalse(AdbParsing.isValidEndpoint("", 37625))
        assertFalse(AdbParsing.isValidEndpoint("192.168.1.20", 0))
        assertFalse(AdbParsing.isValidEndpoint("192.168.1.20", 70000))
        assertFalse(AdbParsing.isValidEndpoint("1.2.3.4; rm -rf", 5555))
    }
}
