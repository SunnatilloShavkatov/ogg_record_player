package uz.plugin.ogg_record_player

import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Thrown when the server answers a download with a non-2xx status. */
class HttpStatusException(val statusCode: Int) : IOException("Download failed with HTTP status $statusCode")

/** Thrown when a download is not an Ogg stream, e.g. an HTML error page served with a 200 status. */
class InvalidAudioFileException : IOException("Downloaded file is not an Ogg stream")

/** Thrown when a download exceeds [RemoteAudioLoader.MAX_BYTES], before it can exhaust memory. */
class ResponseTooLargeException : IOException("Download is larger than ${RemoteAudioLoader.MAX_BYTES} bytes")

/** Downloads a fresh Ogg stream into memory for every request, without storing or reusing it. */
internal object RemoteAudioLoader {

    private const val TIMEOUT_MS = 30_000

    /** Largest accepted download; the Darwin loader enforces the same limit. */
    const val MAX_BYTES = 32 * 1024 * 1024
    private val mainHandler = Handler(Looper.getMainLooper())

    // Two workers at most; idle workers exit when there are no downloads.
    private val executor = ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS, LinkedBlockingQueue()) { runnable ->
        Thread(runnable, "ogg_record_player.download").apply { isDaemon = true }
    }.apply { allowCoreThreadTimeOut(true) }

    fun isRemote(path: String): Boolean =
        path.startsWith("https://", ignoreCase = true) || path.startsWith("http://", ignoreCase = true)

    /** Calls [callback] on the main thread with the downloaded bytes. */
    fun load(url: String, callback: (Result<ByteArray>) -> Unit) {
        executor.execute {
            val result = runCatching { download(url) }
            mainHandler.post { callback(result) }
        }
    }

    private fun download(url: String): ByteArray {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.instanceFollowRedirects = true
            connection.useCaches = false
            connection.setRequestProperty("Cache-Control", "no-cache")
            // Opus is already compressed: gzip would only cost CPU on both ends.
            connection.setRequestProperty("Accept-Encoding", "identity")
            // HttpURLConnection combines DNS, TCP, TLS and response headers in this call.
            val status = connection.responseCode
            if (status !in 200..299) {
                throw HttpStatusException(status)
            }
            if (connection.contentLengthLong > MAX_BYTES) {
                throw ResponseTooLargeException()
            }
            val bytes = connection.inputStream.use { it.readBounded(MAX_BYTES) }
            if (!bytes.hasOggSignature()) {
                throw InvalidAudioFileException()
            }
            return bytes
        } finally {
            connection.disconnect()
        }
    }

    /** Like [InputStream.readBytes], but stops as soon as the stream passes [limit] bytes. */
    private fun InputStream.readBounded(limit: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val count = read(buffer)
            if (count < 0) {
                return output.toByteArray()
            }
            if (output.size() + count > limit) {
                throw ResponseTooLargeException()
            }
            output.write(buffer, 0, count)
        }
    }
}
