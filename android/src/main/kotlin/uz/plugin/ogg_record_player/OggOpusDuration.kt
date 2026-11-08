package uz.plugin.ogg_record_player

import java.io.File
import java.io.RandomAccessFile

/**
 * Reads an Ogg Opus duration from the container alone, without a decoder: the last granule position of the
 * stream minus the encoder pre-skip, at Opus' fixed 48 kHz granule rate (the same value as `op_pcm_total` on iOS).
 * Lets a player report its duration without creating an ExoPlayer, which holds a playback thread, a decoder and
 * an AudioTrack for as long as it lives.
 */
internal object OggOpusDuration {

    private const val GRANULE_RATE = 48_000.0
    private const val PAGE_HEADER_SIZE = 27

    /** Enough for the identification page and for the last pages of any real stream. */
    private const val WINDOW = 64 * 1024

    /** `null` when [bytes] is not an Ogg Opus stream with a usable final granule position. */
    fun of(bytes: ByteArray): Double? = compute(bytes, bytes)

    /** Reads only the first and last [WINDOW] bytes of [file]. */
    fun of(file: File): Double? = runCatching {
        RandomAccessFile(file, "r").use { input ->
            val length = input.length()
            val head = ByteArray(minOf(length, WINDOW.toLong()).toInt())
            input.readFully(head)
            val tailStart = maxOf(0L, length - WINDOW)
            val tail = ByteArray((length - tailStart).toInt())
            input.seek(tailStart)
            input.readFully(tail)
            compute(head, tail)
        }
    }.getOrNull()

    private fun compute(head: ByteArray, tail: ByteArray): Double? {
        val first = pageAt(head, 0) ?: return null
        val payload = first.payloadOffset
        if (!head.matches(payload, "OpusHead") || payload + 12 > head.size) return null
        val preSkip = head.u16(payload + 10)
        val lastGranule = lastGranule(tail, first.serial) ?: return null
        val samples = lastGranule - preSkip
        return if (samples > 0) samples / GRANULE_RATE else null
    }

    /** The granule of the last complete page of [serial] in [bytes] that finishes a packet. */
    private fun lastGranule(bytes: ByteArray, serial: Int): Long? {
        var index = bytes.size - PAGE_HEADER_SIZE
        while (index >= 0) {
            val page = if (bytes.matches(index, "OggS")) pageAt(bytes, index) else null
            // A page that ends no packet carries granule -1; an earlier page of the stream holds the answer.
            if (page != null && page.serial == serial && page.granule >= 0 && page.end <= bytes.size) {
                return page.granule
            }
            index--
        }
        return null
    }

    private class Page(val granule: Long, val serial: Int, val payloadOffset: Int, val end: Int)

    private fun pageAt(bytes: ByteArray, start: Int): Page? {
        if (start + PAGE_HEADER_SIZE > bytes.size || !bytes.matches(start, "OggS") || bytes[start + 4].toInt() != 0) {
            return null
        }
        val segments = bytes[start + 26].toInt() and 0xFF
        val payloadOffset = start + PAGE_HEADER_SIZE + segments
        if (payloadOffset > bytes.size) return null
        var payloadSize = 0
        for (i in 0 until segments) {
            payloadSize += bytes[start + PAGE_HEADER_SIZE + i].toInt() and 0xFF
        }
        return Page(bytes.i64(start + 6), bytes.i32(start + 14), payloadOffset, payloadOffset + payloadSize)
    }

    private fun ByteArray.matches(start: Int, text: String): Boolean =
        start >= 0 && start + text.length <= size && text.indices.all { this[start + it] == text[it].code.toByte() }

    private fun ByteArray.u16(at: Int): Int = (this[at].toInt() and 0xFF) or ((this[at + 1].toInt() and 0xFF) shl 8)

    private fun ByteArray.i32(at: Int): Int = (0 until 4).fold(0) { acc, i -> acc or ((this[at + i].toInt() and 0xFF) shl (8 * i)) }

    private fun ByteArray.i64(at: Int): Long =
        (0 until 8).fold(0L) { acc, i -> acc or ((this[at + i].toLong() and 0xFF) shl (8 * i)) }
}
