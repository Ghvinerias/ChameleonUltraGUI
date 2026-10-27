package io.chameleon.wearsync

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.ChannelClient
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Channels:
 *  - MethodChannel `io.chameleon.ultra/wear_sync`
 *  - EventChannel  `io.chameleon.ultra/wear_sync/events` (peer, message, incomingBulk, chunk,
 *    bulkEnd, bulkAborted maps; see docs/wear-sync-plugin.md)
 *
 * Every Wearable call is guarded: if Google Play Services or the Wearable API is missing the
 * plugin reports `available = false` instead of throwing.
 */
class WearSyncPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private class Transfer(
        val id: String,
        val channel: ChannelClient.Channel,
        val outgoing: Boolean,
    ) {
        @Volatile var out: OutputStream? = null
        @Volatile var input: InputStream? = null
        @Volatile var ended = false
        @Volatile var cancelledLocally = false
        val finished = AtomicBoolean(false)
    }

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool()
    private var sink: EventChannel.EventSink? = null

    private val transfers = ConcurrentHashMap<String, Transfer>() // by channel path
    @Volatile private var peer: Node? = null
    private var lastPeerKey: String? = null
    private var messageClient: MessageClient? = null
    private var channelClient: ChannelClient? = null
    private var capabilityClient: CapabilityClient? = null
    private var listening = false

    private val messageListener = MessageClient.OnMessageReceivedListener { onMessage(it) }
    private val capabilityListener = CapabilityClient.OnCapabilityChangedListener { updatePeer(it.nodes) }
    private val channelCallback = object : ChannelClient.ChannelCallback() {
        override fun onChannelOpened(channel: ChannelClient.Channel) = onChannelOpenedImpl(channel)
        override fun onChannelClosed(channel: ChannelClient.Channel, closeReason: Int, appSpecificErrorCode: Int) =
            onChannelClosedImpl(channel, closeReason, appSpecificErrorCode)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "io.chameleon.ultra/wear_sync")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "io.chameleon.ultra/wear_sync/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        stopListening()
        io.shutdown()
    }

    // ---- EventChannel -------------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        startListening()
    }

    override fun onCancel(arguments: Any?) {
        stopListening()
        sink = null
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    // ---- MethodChannel ------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(status())
            "getPeer" -> io.execute { reply(result) { peerMap(refreshPeer()) } }
            "sendMessage" -> sendMessage(call.argument<ByteArray>("bytes"), result)
            "openBulk" -> openBulk(call.argument<String>("transferId"), call.argument<ByteArray>("header"), result)
            "sendChunk" -> sendFrame(call.argument<String>("transferId"), call.argument<Int>("index"), call.argument<ByteArray>("bytes"), result)
            "endBulk" -> endBulk(call.argument<String>("transferId"), result)
            "cancelBulk" -> cancelBulk(call.argument<String>("transferId"), result)
            else -> result.notImplemented()
        }
    }

    private fun reply(result: MethodChannel.Result, block: () -> Any?) {
        try {
            val v = block()
            main.post { result.success(v) }
        } catch (e: WearError) {
            main.post { result.error(e.code, e.message, null) }
        } catch (e: ApiException) {
            val code = if (isUnavailable(e)) "unavailable" else "failed"
            main.post { result.error(code, e.message, null) }
        } catch (e: Throwable) {
            main.post { result.error("failed", e.message, null) }
        }
    }

    private class WearError(val code: String, message: String) : Exception(message)

    private fun isUnavailable(e: ApiException) = e.statusCode == 17 // API_UNAVAILABLE

    /** Null when usable, else a short reason. */
    private fun unavailableReason(): String? = try {
        val code = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
        if (code == ConnectionResult.SUCCESS) null else "play_services_$code"
    } catch (t: Throwable) {
        "play_services_missing"
    }

    private fun status(): Map<String, Any?> {
        val reason = unavailableReason()
        return mapOf(
            "available" to (reason == null),
            "reason" to reason,
            "maxMessageBytes" to MAX_MESSAGE_BYTES,
        )
    }

    private fun requireUsable() {
        unavailableReason()?.let { throw WearError("unavailable", it) }
    }

    private fun peerMap(node: Node?): Map<String, Any?>? =
        node?.let { mapOf("id" to it.id, "name" to it.displayName, "nearby" to it.isNearby) }

    private fun refreshPeer(): Node? {
        if (unavailableReason() != null) return null
        return try {
            val info = Tasks.await(
                Wearable.getCapabilityClient(context).getCapability(CAPABILITY, CapabilityClient.FILTER_REACHABLE),
            )
            pickPeer(info.nodes)
        } catch (t: Throwable) {
            null
        }
    }

    private fun pickPeer(nodes: Set<Node>): Node? {
        val p = nodes.firstOrNull { it.isNearby } ?: nodes.firstOrNull()
        peer = p
        return p
    }

    private fun updatePeer(nodes: Set<Node>) {
        val p = pickPeer(nodes)
        val key = p?.id
        if (key == lastPeerKey) return
        lastPeerKey = key
        emit(mapOf("event" to "peer", "available" to (p != null), "id" to p?.id, "name" to p?.displayName, "nearby" to p?.isNearby))
    }

    private fun startListening() {
        if (listening) return
        if (unavailableReason() != null) {
            emit(mapOf("event" to "peer", "available" to false))
            return
        }
        listening = true
        try {
            val mc = Wearable.getMessageClient(context)
            val cc = Wearable.getChannelClient(context)
            val cap = Wearable.getCapabilityClient(context)
            messageClient = mc
            channelClient = cc
            capabilityClient = cap
            mc.addListener(messageListener)
            cc.registerChannelCallback(channelCallback)
            cap.addListener(capabilityListener, CAPABILITY)
        } catch (t: Throwable) {
            stopListening()
            emit(mapOf("event" to "peer", "available" to false))
            return
        }
        io.execute {
            lastPeerKey = null
            val p = refreshPeer()
            lastPeerKey = p?.id
            emit(mapOf("event" to "peer", "available" to (p != null), "id" to p?.id, "name" to p?.displayName, "nearby" to p?.isNearby))
        }
    }

    private fun stopListening() {
        runCatching { messageClient?.removeListener(messageListener) }
        runCatching { channelClient?.unregisterChannelCallback(channelCallback) }
        runCatching { capabilityClient?.removeListener(capabilityListener) }
        for (t in transfers.values) {
            t.cancelledLocally = true
            runCatching { channelClient?.close(t.channel, AbortDecider.CANCEL_CODE) }
        }
        transfers.clear()
        messageClient = null
        channelClient = null
        capabilityClient = null
        listening = false
        peer = null
        lastPeerKey = null
    }

    // ---- Messages -----------------------------------------------------------------------

    private fun onMessage(event: MessageEvent) {
        if (event.path != PATH_MESSAGE) return
        emit(mapOf("event" to "message", "bytes" to event.data))
    }

    private fun sendMessage(bytes: ByteArray?, result: MethodChannel.Result) {
        io.execute {
            reply(result) {
                requireUsable()
                if (bytes == null) throw WearError("bad_args", "bytes missing")
                if (bytes.size > MAX_MESSAGE_BYTES) throw WearError("too_large", "message ${bytes.size} > $MAX_MESSAGE_BYTES")
                val node = peer ?: refreshPeer() ?: throw WearError("no_peer", "no peer")
                Tasks.await(Wearable.getMessageClient(context).sendMessage(node.id, PATH_MESSAGE, bytes))
                null
            }
        }
    }

    // ---- Bulk ---------------------------------------------------------------------------

    private fun bulkPath(id: String) = PATH_BULK + id

    private fun openBulk(id: String?, header: ByteArray?, result: MethodChannel.Result) {
        io.execute {
            reply(result) {
                requireUsable()
                if (id == null || header == null) throw WearError("bad_args", "transferId/header missing")
                val cc = channelClient ?: Wearable.getChannelClient(context)
                val node = peer ?: refreshPeer() ?: throw WearError("no_peer", "no peer")
                val channel = Tasks.await(cc.openChannel(node.id, bulkPath(id)))
                val t = Transfer(id, channel, outgoing = true)
                transfers[channel.path] = t
                try {
                    val out = Tasks.await(cc.getOutputStream(channel))
                    t.out = out
                    BulkFraming.write(out, BulkFraming.HEADER, header)
                } catch (e: Throwable) {
                    transfers.remove(channel.path)
                    runCatching { cc.close(channel) }
                    throw WearError("link_lost", e.message ?: "open failed")
                }
                null
            }
        }
    }

    private fun outgoing(id: String?): Transfer {
        val t = transfers.values.firstOrNull { it.id == id && it.outgoing }
            ?: throw WearError("no_transfer", "unknown or finished transfer $id")
        if (t.finished.get()) throw WearError("no_transfer", "transfer finished")
        return t
    }

    private fun sendFrame(id: String?, index: Int?, bytes: ByteArray?, result: MethodChannel.Result) {
        io.execute {
            reply(result) {
                val t = outgoing(id)
                if (index == null || bytes == null) throw WearError("bad_args", "index/bytes missing")
                val out = t.out ?: throw WearError("no_transfer", "stream not open")
                try {
                    synchronized(out) { BulkFraming.write(out, index, bytes) }
                } catch (e: Throwable) {
                    abortTransfer(t, "linkLost")
                    throw WearError("link_lost", e.message ?: "write failed")
                }
                null
            }
        }
    }

    private fun endBulk(id: String?, result: MethodChannel.Result) {
        io.execute {
            reply(result) {
                val t = outgoing(id)
                val out = t.out ?: throw WearError("no_transfer", "stream not open")
                try {
                    synchronized(out) { BulkFraming.write(out, BulkFraming.END, ByteArray(0)) }
                } catch (e: Throwable) {
                    abortTransfer(t, "linkLost")
                    throw WearError("link_lost", e.message ?: "write failed")
                }
                t.ended = true
                // The receiver closes the channel after reading END; close ourselves if it never does.
                main.postDelayed({ if (transfers.containsKey(t.channel.path)) closeQuietly(t, false) }, END_CLOSE_TIMEOUT_MS)
                null
            }
        }
    }

    private fun cancelBulk(id: String?, result: MethodChannel.Result) {
        io.execute {
            reply(result) {
                val t = transfers.values.firstOrNull { it.id == id }
                if (t != null) closeQuietly(t, true)
                null
            }
        }
    }

    private fun closeQuietly(t: Transfer, cancel: Boolean) {
        if (cancel) t.cancelledLocally = true
        t.finished.set(true)
        transfers.remove(t.channel.path)
        runCatching {
            if (cancel) channelClient?.close(t.channel, AbortDecider.CANCEL_CODE)
            else channelClient?.close(t.channel)
        }
    }

    private fun abortTransfer(t: Transfer, reason: String) {
        if (t.finished.compareAndSet(false, true)) {
            transfers.remove(t.channel.path)
            runCatching { channelClient?.close(t.channel) }
            emit(mapOf("event" to "bulkAborted", "transferId" to t.id, "reason" to reason))
        }
    }

    private fun onChannelOpenedImpl(channel: ChannelClient.Channel) {
        val path = channel.path
        if (!path.startsWith(PATH_BULK)) return
        val id = path.substring(PATH_BULK.length)
        val t = Transfer(id, channel, outgoing = false)
        transfers[path] = t
        io.execute {
            val cc = channelClient ?: return@execute
            try {
                val input = Tasks.await(cc.getInputStream(channel))
                t.input = input
                val header = BulkFraming.read(input)
                if (header == null || header.index != BulkFraming.HEADER) throw java.io.IOException("missing header")
                emit(mapOf("event" to "incomingBulk", "transferId" to id, "header" to header.payload))
                while (true) {
                    val f = BulkFraming.read(input) ?: break
                    if (f.index == BulkFraming.END) {
                        t.ended = true
                        t.finished.set(true)
                        emit(mapOf("event" to "bulkEnd", "transferId" to id))
                        transfers.remove(path)
                        runCatching { cc.close(channel) }
                        return@execute
                    }
                    emit(mapOf("event" to "chunk", "transferId" to id, "index" to f.index, "bytes" to f.payload))
                }
                // EOF without END: onChannelClosed decides the reason; fall back if it never comes.
                main.postDelayed({ if (!t.finished.get()) abortTransfer(t, "linkLost") }, CLOSE_GRACE_MS)
            } catch (e: Throwable) {
                if (!t.finished.get()) {
                    main.postDelayed({ if (!t.finished.get()) abortTransfer(t, "linkLost") }, CLOSE_GRACE_MS)
                }
            }
        }
    }

    private fun onChannelClosedImpl(channel: ChannelClient.Channel, closeReason: Int, errorCode: Int) {
        val t = transfers.remove(channel.path) ?: return
        if (!t.finished.compareAndSet(false, true)) return
        val reason = AbortDecider.decide(closeReason, errorCode, t.ended, t.cancelledLocally) ?: return
        emit(mapOf("event" to "bulkAborted", "transferId" to t.id, "reason" to reason))
    }

    companion object {
        const val CAPABILITY = "chameleon_ultra_sync"
        const val PATH_MESSAGE = "/chameleon/sync/msg"
        const val PATH_BULK = "/chameleon/sync/bulk/"
        const val MAX_MESSAGE_BYTES = 100 * 1024
        private const val END_CLOSE_TIMEOUT_MS = 30_000L
        private const val CLOSE_GRACE_MS = 1_500L
    }
}
