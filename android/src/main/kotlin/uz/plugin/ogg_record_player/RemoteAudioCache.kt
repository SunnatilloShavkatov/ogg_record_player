package uz.plugin.ogg_record_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Thrown when the server answers a download with a non-2xx status. */
class HttpStatusException(val statusCode: Int) : IOException("Download failed with HTTP status $statusCode")

/** Thrown when a download is not an Ogg stream, e.g. an HTML error page served with a 200 status. */
class InvalidAudioFileException : IOException("Downloaded file is not an Ogg stream")

/**
 * Downloads remote (`http`/`https`) Ogg Opus files into the cache directory so [AudioPlayer] plays them from disk.
 * A download is reused for [MAX_AGE_MS], then fetched again; concurrent requests for the same URL share one
 * download. Mirrors the Darwin `RemoteAudioCache`: same flow, file names and error cases.
 */
internal object RemoteAudioCache {

    private const val MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000
    private const val TIMEOUT_MS = 30_000
    private const val BUFFER_SIZE = 64 * 1024

    private val mainHandler = Handler(Looper.getMainLooper())

    // Two workers at most, and idle ones exit, so the cache holds no thread while nothing downloads.
    private val executor = ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS, LinkedBlockingQueue()) { runnable ->
        Thread(runnable, "ogg_record_player.cache").apply { isDaemon = true }
    }.apply { allowCoreThreadTimeOut(true) }

    /** Pending callbacks per remote URL. Accessed on the main thread only. */
    private val pending = HashMap<String, MutableList<(Result<File>) -> Unit>>()

    fun isRemote(path: String): Boolean =
        path.startsWith("https://", ignoreCase = true) || path.startsWith("http://", ignoreCase = true)

    /** Deletes expired files in the background. Called once when the plugin attaches. */
    fun purgeExpiredFiles(context: Context) {
        val directory = directory(context)
        executor.execute {
            directory.listFiles()?.forEach { file ->
                if (isExpired(file)) file.delete()
            }
        }
    }

    /** Calls [callback] on the main thread with a local file holding the contents of [url]. */
    fun localFile(context: Context, url: String, callback: (Result<File>) -> Unit) {
        pending[url]?.let {
            it.add(callback)
            return
        }
        pending[url] = mutableListOf(callback)

        val destination = cachedFile(context, url)
        executor.execute {
            val result = runCatching {
                if (!destination.exists() || isExpired(destination)) {
                    download(url, destination)
                }
                destination
            }
            mainHandler.post { finish(url, result) }
        }
    }

    /** Deletes the cached copy of [url], e.g. when it turned out not to be a playable Ogg Opus file. */
    fun removeCachedFile(context: Context, url: String) {
        val file = cachedFile(context, url)
        executor.execute { file.delete() }
    }

    private fun download(url: String, destination: File) {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.instanceFollowRedirects = true
            // Opus is already compressed: gzip would only cost CPU on both ends.
            connection.setRequestProperty("Accept-Encoding", "identity")
            val status = connection.responseCode
            if (status !in 200..299) {
                throw HttpStatusException(status)
            }
            destination.parentFile?.mkdirs()
            // Written next to the destination and renamed, so a cancelled download never looks complete.
            val partial = File(destination.path + ".part")
            try {
                connection.inputStream.use { input ->
                    partial.outputStream().use { output -> input.copyTo(output, BUFFER_SIZE) }
                }
                if (!hasOggSignature(partial)) {
                    throw InvalidAudioFileException()
                }
                if (!partial.renameTo(destination)) {
                    throw IOException("Failed to move download into the cache")
                }
                // The age is counted from the download.
                destination.setLastModified(System.currentTimeMillis())
            } finally {
                partial.delete()
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun finish(url: String, result: Result<File>) {
        pending.remove(url)?.forEach { it(result) }
    }

    private fun directory(context: Context) = File(context.cacheDir, "ogg_record_player")

    private fun cachedFile(context: Context, url: String): File {
        val digest = MessageDigest.getInstance("SHA-256").digest(url.toByteArray(Charsets.UTF_8))
        val name = digest.joinToString("") { "%02x".format(it) }
        return File(directory(context), "$name.ogg")
    }

    private fun isExpired(file: File): Boolean =
        System.currentTimeMillis() - file.lastModified() > MAX_AGE_MS

    private fun hasOggSignature(file: File): Boolean {
        val header = ByteArray(4)
        val read = file.inputStream().use { it.read(header) }
        return read == 4 && header.hasOggSignature()
    }
}
