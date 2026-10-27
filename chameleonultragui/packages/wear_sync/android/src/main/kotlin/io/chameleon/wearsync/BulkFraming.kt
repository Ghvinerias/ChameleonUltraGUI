package io.chameleon.wearsync

import java.io.DataInputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer

/**
 * Wire framing for one bulk transfer carried over a single ChannelClient stream.
 *
 * Frame = int32 index (big endian) | int32 payload length | payload.
 * The first frame has index [HEADER] and carries the opaque header bytes; chunks use their
 * 0-based index; [END] closes the transfer. Pure java.io so it is unit-testable on the JVM.
 */
object BulkFraming {
    const val HEADER = -1
    const val END = -2

    /** Upper bound for one frame payload; guards against corrupt length fields. */
    const val MAX_PAYLOAD = 8 * 1024 * 1024

    class Frame(val index: Int, val payload: ByteArray)

    fun encode(index: Int, payload: ByteArray): ByteArray {
        require(payload.size <= MAX_PAYLOAD) { "payload too large: ${payload.size}" }
        return ByteBuffer.allocate(8 + payload.size).putInt(index).putInt(payload.size).put(payload).array()
    }

    /** Writes one frame with a single write call and flushes. */
    fun write(out: OutputStream, index: Int, payload: ByteArray) {
        out.write(encode(index, payload))
        out.flush()
    }

    /**
     * Reads one frame. Returns null on clean end of stream at a frame boundary; throws
     * [EOFException] if the stream ends inside a frame and [IOException] for an invalid length.
     */
    fun read(input: InputStream): Frame? {
        val data = DataInputStream(input)
        val first = input.read()
        if (first < 0) return null
        val rest = ByteArray(7)
        data.readFully(rest)
        val bb = ByteBuffer.allocate(8).put(first.toByte()).put(rest)
        bb.flip()
        val index = bb.int
        val length = bb.int
        if (length < 0 || length > MAX_PAYLOAD) throw IOException("invalid frame length $length")
        val payload = ByteArray(length)
        data.readFully(payload)
        return Frame(index, payload)
    }
}

/** Maps ChannelClient close information to the Dart-side abort reason. */
object AbortDecider {
    // ChannelClient.ChannelCallback.CLOSE_REASON_* values.
    const val CLOSE_NORMAL = 0
    const val CLOSE_DISCONNECTED = 1
    const val CLOSE_REMOTE = 2
    const val CLOSE_LOCAL = 3

    /** App-specific error code passed to `ChannelClient.close` when cancelling. */
    const val CANCEL_CODE = 7

    /** Returns `cancelledByPeer`, `linkLost` or `error`; null if the close is not an abort. */
    fun decide(closeReason: Int, errorCode: Int, ended: Boolean, cancelledLocally: Boolean): String? {
        if (ended || cancelledLocally) return null
        return when (closeReason) {
            CLOSE_DISCONNECTED -> "linkLost"
            CLOSE_REMOTE, CLOSE_NORMAL -> if (errorCode == 0 || errorCode == CANCEL_CODE) "cancelledByPeer" else "error"
            else -> "error"
        }
    }
}
