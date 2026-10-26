package io.chameleon.adbwifi

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.flyfishxu.kadb.Kadb
import com.flyfishxu.kadb.cert.KadbCert
import com.flyfishxu.kadb.cert.OkioFilePrivateKeyStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking
import okio.ForwardingSource
import okio.Buffer
import okio.Path.Companion.toPath
import okio.Source
import okio.buffer
import okio.source
import java.io.File
import java.util.concurrent.Executors

/**
 * Channels:
 *  - MethodChannel `io.chameleon.ultra/adb_wifi`
 *  - EventChannel  `io.chameleon.ultra/adb_wifi/progress` (install progress, see [emitProgress])
 *
 * The ADB private key lives in `<filesDir>/adb_wifi/adbkey.pem` (app-private storage) and never
 * leaves it; nothing here exports it.
 */
class AdbWifiPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var sink: EventChannel.EventSink? = null

    @Volatile
    private var kadb: Kadb? = null
    private var keyStoreConfigured = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "io.chameleon.ultra/adb_wifi")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "io.chameleon.ultra/adb_wifi/progress")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        worker.execute { closeConnection() }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emitProgress(sent: Long, total: Long) {
        main.post { sink?.success(mapOf("op" to "install", "sent" to sent, "total" to total)) }
    }

    private fun ensureKeyStore() {
        if (keyStoreConfigured) return
        val dir = File(context.filesDir, "adb_wifi").apply { mkdirs() }
        KadbCert.configure(OkioFilePrivateKeyStore(File(dir, "adbkey.pem").absolutePath.toPath()))
        keyStoreConfigured = true
    }

    private fun closeConnection() {
        try {
            kadb?.close()
        } catch (_: Throwable) {
        }
        kadb = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            try {
                val value = handle(call)
                main.post { result.success(value) }
            } catch (e: AdbPluginException) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: Throwable) {
                main.post { result.error(AdbErrorCode.OTHER, e.message ?: e.javaClass.name, null) }
            }
        }
    }

    private class AdbPluginException(val code: String, message: String?) : Exception(message)

    private fun requireEndpoint(host: String?, port: Int?): Pair<String, Int> {
        if (host == null || port == null || !AdbParsing.isValidEndpoint(host, port)) {
            throw AdbPluginException(AdbErrorCode.OTHER, "Invalid host or port")
        }
        return host to port
    }

    private fun requireConnection(): Kadb =
        kadb ?: throw AdbPluginException(AdbErrorCode.NOT_CONNECTED, "Not connected to a watch")

    private fun handle(call: MethodCall): Any? {
        ensureKeyStore()
        when (call.method) {
            "pair" -> {
                val (host, port) = requireEndpoint(call.argument("host"), call.argument("port"))
                val code = call.argument<String>("code")
                if (code.isNullOrBlank()) throw AdbPluginException(AdbErrorCode.PAIRING_FAILED, "Pairing code is empty")
                try {
                    runBlocking { Kadb.pair(host, port, code) }
                } catch (e: Throwable) {
                    throw AdbPluginException(AdbErrorCode.PAIRING_FAILED, e.message ?: e.javaClass.name)
                }
                return null
            }
            "connect" -> {
                val (host, port) = requireEndpoint(call.argument("host"), call.argument("port"))
                closeConnection()
                val k = Kadb.create(host, port, connectTimeout = 10_000, socketTimeout = 30_000)
                try {
                    // Kadb connects lazily; probe so failures surface here.
                    val probe = k.shell("echo adb_wifi_ok")
                    if (!probe.allOutput.contains("adb_wifi_ok")) {
                        throw IllegalStateException("Unexpected probe output: ${probe.allOutput}")
                    }
                } catch (e: Throwable) {
                    try {
                        k.close()
                    } catch (_: Throwable) {
                    }
                    throw AdbPluginException(
                        AdbParsing.classifyConnectFailure(e.javaClass.name, e.message),
                        e.message ?: e.javaClass.name
                    )
                }
                kadb = k
                return null
            }
            "install" -> {
                val k = requireConnection()
                val path = call.argument<String>("apkPath") ?: throw AdbPluginException(AdbErrorCode.OTHER, "apkPath missing")
                val file = File(path)
                if (!file.isFile) throw AdbPluginException(AdbErrorCode.OTHER, "APK not found: $path")
                val total = file.length()
                try {
                    val progress = ProgressSource(file.source(), total, ::emitProgress)
                    k.install(progress.buffer(), total, "-r")
                } catch (e: Throwable) {
                    val msg = e.message ?: e.javaClass.name
                    val code = if (msg.contains("Install failed")) {
                        AdbParsing.classifyInstallFailure(msg)
                    } else {
                        AdbParsing.classifyConnectFailure(e.javaClass.name, msg)
                    }
                    throw AdbPluginException(code, msg)
                }
                return null
            }
            "uninstall" -> {
                val pkg = call.argument<String>("packageName") ?: throw AdbPluginException(AdbErrorCode.OTHER, "packageName missing")
                requirePackageName(pkg)
                try {
                    requireConnection().uninstall(pkg)
                } catch (e: AdbPluginException) {
                    throw e
                } catch (e: Throwable) {
                    throw AdbPluginException(AdbErrorCode.OTHER, e.message ?: e.javaClass.name)
                }
                return null
            }
            "launch" -> {
                val pkg = call.argument<String>("packageName") ?: throw AdbPluginException(AdbErrorCode.OTHER, "packageName missing")
                requirePackageName(pkg)
                val k = requireConnection()
                val monkey = k.shell("monkey -p $pkg -c android.intent.category.LAUNCHER 1")
                if (monkey.exitCode == 0 && !monkey.allOutput.contains("No activities found")) return null
                val resolved = AdbParsing.parseResolvedActivity(
                    k.shell("cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $pkg").allOutput
                ) ?: throw AdbPluginException(AdbErrorCode.OTHER, "No launcher activity found for $pkg")
                val start = k.shell("am start -n $resolved")
                if (start.exitCode != 0 || start.allOutput.contains("Error")) {
                    throw AdbPluginException(AdbErrorCode.OTHER, start.allOutput.trim())
                }
                return null
            }
            "installedVersion" -> {
                val pkg = call.argument<String>("packageName") ?: throw AdbPluginException(AdbErrorCode.OTHER, "packageName missing")
                requirePackageName(pkg)
                val out = requireConnection().shell("dumpsys package $pkg").allOutput
                val v = AdbParsing.parsePackageVersion(out) ?: return null
                return mapOf("versionName" to v.versionName, "versionCode" to v.versionCode)
            }
            "deviceInfo" -> {
                val k = requireConnection()
                fun prop(name: String) = k.shell("getprop $name").output.trim()
                return mapOf(
                    "model" to prop("ro.product.model"),
                    "abiList" to prop("ro.product.cpu.abilist"),
                    "sdk" to prop("ro.build.version.sdk")
                )
            }
            "isConnected" -> return kadb?.connectionCheck() == true
            "hasKeys" -> return KadbCert.exportPrivateKeyOrNull() != null
            "disconnect" -> {
                closeConnection()
                return null
            }
            "forgetKeys" -> {
                closeConnection()
                KadbCert.clear()
                return null
            }
            else -> throw AdbPluginException(AdbErrorCode.OTHER, "Unknown method ${call.method}")
        }
    }

    private fun requirePackageName(pkg: String) {
        if (!Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$").matches(pkg)) {
            throw AdbPluginException(AdbErrorCode.OTHER, "Invalid package name")
        }
    }

    /** Reports bytes read from the APK to [onProgress], throttled to ~1% steps. */
    private class ProgressSource(
        delegate: Source,
        private val total: Long,
        private val onProgress: (Long, Long) -> Unit
    ) : ForwardingSource(delegate) {
        private var sent = 0L
        private var lastReported = -1L

        override fun read(sink: Buffer, byteCount: Long): Long {
            val n = super.read(sink, byteCount)
            if (n > 0) {
                sent += n
                val step = (sent * 100) / maxOf(total, 1)
                if (step != lastReported) {
                    lastReported = step
                    onProgress(sent, total)
                }
            }
            return n
        }
    }
}
