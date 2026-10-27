package io.chameleon.wearsync

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.nio.ByteBuffer

class BulkFramingTest {
    private fun roundTrip(frames: List<Pair<Int, ByteArray>>): List<BulkFraming.Frame> {
        val out = ByteArrayOutputStream()
        frames.forEach { BulkFraming.write(out, it.first, it.second) }
        val input = ByteArrayInputStream(out.toByteArray())
        val read = mutableListOf<BulkFraming.Frame>()
        while (true) read += BulkFraming.read(input) ?: break
        return read
    }

    @Test
    fun headerChunksAndEndRoundTrip() {
        val chunk = ByteArray(40_000) { (it % 251).toByte() }
        val frames = roundTrip(
            listOf(
                BulkFraming.HEADER to "{\"a\":1}".toByteArray(),
                0 to chunk,
                5 to byteArrayOf(1, 2, 3),
                BulkFraming.END to ByteArray(0),
            ),
        )
        assertEquals(listOf(BulkFraming.HEADER, 0, 5, BulkFraming.END), frames.map { it.index })
        assertArrayEquals(chunk, frames[1].payload)
        assertEquals(0, frames[3].payload.size)
    }

    @Test
    fun cleanEofReturnsNull() {
        assertNull(BulkFraming.read(ByteArrayInputStream(ByteArray(0))))
    }

    @Test
    fun truncatedFrameThrowsEof() {
        val bytes = BulkFraming.encode(3, ByteArray(100))
        try {
            BulkFraming.read(ByteArrayInputStream(bytes.copyOf(50)))
            fail()
        } catch (e: EOFException) {
            // expected
        }
        try {
            BulkFraming.read(ByteArrayInputStream(bytes.copyOf(3)))
            fail()
        } catch (e: EOFException) {
        }
    }

    @Test
    fun invalidLengthRejected() {
        val bad = ByteBuffer.allocate(8).putInt(1).putInt(Int.MAX_VALUE).array()
        try {
            BulkFraming.read(ByteArrayInputStream(bad))
            fail()
        } catch (e: IOException) {
            assertTrue(e.message!!.contains("invalid"))
        }
        val negative = ByteBuffer.allocate(8).putInt(1).putInt(-5).array()
        try {
            BulkFraming.read(ByteArrayInputStream(negative))
            fail()
        } catch (e: IOException) {
        }
    }

    @Test
    fun encodeRejectsOversizedPayload() {
        try {
            BulkFraming.encode(0, ByteArray(BulkFraming.MAX_PAYLOAD + 1))
            fail()
        } catch (e: IllegalArgumentException) {
        }
    }

    @Test
    fun abortDeciderMapping() {
        val d = AbortDecider
        assertNull(d.decide(d.CLOSE_NORMAL, 0, ended = true, cancelledLocally = false))
        assertNull(d.decide(d.CLOSE_LOCAL, d.CANCEL_CODE, ended = false, cancelledLocally = true))
        assertEquals("linkLost", d.decide(d.CLOSE_DISCONNECTED, 0, false, false))
        assertEquals("cancelledByPeer", d.decide(d.CLOSE_REMOTE, d.CANCEL_CODE, false, false))
        assertEquals("cancelledByPeer", d.decide(d.CLOSE_NORMAL, 0, false, false))
        assertEquals("error", d.decide(d.CLOSE_REMOTE, 99, false, false))
        assertEquals("error", d.decide(d.CLOSE_LOCAL, 0, false, false))
    }
}
