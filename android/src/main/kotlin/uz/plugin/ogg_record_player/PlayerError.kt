package uz.plugin.ogg_record_player

import io.flutter.plugin.common.MethodChannel
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
    IO_ERROR("IO_ERROR", "Failed to store downloaded audio"),
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
    }
}

internal fun MethodChannel.Result.fail(playerError: PlayerError, details: String?) {
    error(playerError.code, playerError.message, details)
}

/** Every Ogg page starts with "OggS". */
internal fun ByteArray.hasOggSignature(): Boolean =
    size >= 4 && this[0] == 'O'.code.toByte() && this[1] == 'g'.code.toByte() &&
        this[2] == 'g'.code.toByte() && this[3] == 'S'.code.toByte()
