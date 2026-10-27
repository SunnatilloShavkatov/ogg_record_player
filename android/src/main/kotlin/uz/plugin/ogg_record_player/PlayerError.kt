package uz.plugin.ogg_record_player

import androidx.media3.common.PlaybackException
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException

/** Error codes of the `createFrom*` methods, shared with Darwin (`PlayerError` in Swift) and mapped to `OggOpusPlayerException`. */
internal enum class PlayerError(val code: String, val message: String) {
    INVALID_ARGUMENT("INVALID_ARGUMENT", "Invalid audio source"),
    FILE_NOT_FOUND("FILE_NOT_FOUND", "Audio file does not exist"),
    NETWORK_ERROR("NETWORK_ERROR", "Failed to download audio"),
    HTTP_ERROR("HTTP_ERROR", "Server rejected the audio request"),
    INVALID_FILE("INVALID_FILE", "File is not a playable Ogg Opus stream"),
    IO_ERROR("IO_ERROR", "Failed to read audio data"),
    UNKNOWN("UNKNOWN", "Failed to create player");

    companion object {
        fun from(throwable: Throwable): PlayerError = when (throwable) {
            is HttpStatusException -> HTTP_ERROR
            is InvalidAudioFileException -> INVALID_FILE
            is UnknownHostException, is SocketTimeoutException, is SSLException,
            is java.net.ConnectException, is java.net.SocketException -> NETWORK_ERROR
            is IOException -> IO_ERROR
            else -> UNKNOWN
        }

        /** Playback failures after creation: unparsable or undecodable audio versus unreadable data. */
        fun from(error: PlaybackException): PlayerError = when (error.errorCode) {
            in PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED..PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED -> INVALID_FILE
            in PlaybackException.ERROR_CODE_IO_UNSPECIFIED until PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED -> IO_ERROR
            else -> UNKNOWN
        }
    }
}

internal fun MethodChannel.Result.fail(playerError: PlayerError, details: String?) {
    error(playerError.code, playerError.message, details)
}

/** Reads only the first four bytes of the file. */
internal fun File.hasOggSignature(): Boolean = inputStream().use { stream ->
    val header = ByteArray(4)
    var read = 0
    while (read < header.size) {
        val count = stream.read(header, read, header.size - read)
        if (count < 0) break
        read += count
    }
    read == header.size && header.hasOggSignature()
}

/** Every Ogg page starts with "OggS". */
internal fun ByteArray.hasOggSignature(): Boolean =
    size >= 4 && this[0] == 'O'.code.toByte() && this[1] == 'g'.code.toByte() &&
        this[2] == 'g'.code.toByte() && this[3] == 'S'.code.toByte()
