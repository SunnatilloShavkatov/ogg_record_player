package uz.plugin.ogg_record_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.MediaSource
import uz.plugin.ogg_record_player.OggRecordPlayerApi.CreateCallback
import uz.plugin.ogg_record_player.OggRecordPlayerApi.PlayerListener
import uz.plugin.ogg_record_player.OggRecordPlayerApi.RecorderListener
import java.io.File
import java.io.IOException
import java.util.Collections
import kotlin.concurrent.thread

/**
 * The players and recorders of one attached Flutter engine, behind [OggRecordPlayerApi]. Players are used on the
 * main thread only: Dart already runs there (merged UI/platform thread), and calls from elsewhere are posted.
 * Once [detach]ed, the host emits nothing more, so a detached engine's events never reach a new one.
 */
@OptIn(UnstableApi::class)
internal class OggRecordPlayerHost(private val context: Context) {

    companion object {
        /** The host of the attached engine; `null` while none is attached. */
        @Volatile
        var current: OggRecordPlayerHost? = null

        private var lastGeneratedId = 0

        @Synchronized
        private fun generateId(): Int {
            lastGeneratedId++
            return lastGeneratedId
        }

        private val mainHandler = Handler(Looper.getMainLooper())

        /**
         * A cold first player spends part of its setup on Media3 listing the device's Opus decoders. The list is
         * cached process-wide, so querying it here off main lets the first real player skip it. Audio focus is
         * untouched.
         */
        fun warmUp(callback: OggRecordPlayerApi.DoneCallback) {
            thread(name = "ogg_record_player.warmUp", isDaemon = true) {
                runCatching { MediaCodecUtil.getDecoderInfos(MimeTypes.AUDIO_OPUS, false, false) }
                mainHandler.post { callback.onDone() }
            }
        }

        private fun onMain(block: () -> Unit) {
            if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
        }
    }

    @Volatile
    private var attached = true

    @Volatile
    private var playerListener: PlayerListener? = null

    @Volatile
    private var recorderListener: RecorderListener? = null

    private val players: MutableMap<Int, AudioPlayer> = Collections.synchronizedMap(mutableMapOf())

    private val recorders = RecorderRegistry(context, ::generateId, object : RecorderListener {
        override fun onCanceled(recorderId: Int, reason: Int) {
            if (attached) recorderListener?.onCanceled(recorderId, reason)
        }

        override fun onStartFailed(recorderId: Int, error: String) {
            if (attached) recorderListener?.onStartFailed(recorderId, error)
        }

        override fun onFinished(recorderId: Int, durationMillis: Long, waveform: ByteArray) {
            if (attached) recorderListener?.onFinished(recorderId, durationMillis, waveform)
        }
    })

    fun setListeners(playerListener: PlayerListener?, recorderListener: RecorderListener?) {
        this.playerListener = playerListener
        this.recorderListener = recorderListener
    }

    // Same checks as Darwin, so both platforms report a missing file the same way instead of an idle player.
    fun createFromFile(path: String?, callback: CreateCallback) = onMain {
        if (path.isNullOrEmpty()) {
            callback.fail(PlayerError.INVALID_ARGUMENT, "path must be a non-empty string")
            return@onMain
        }
        val file = File(path)
        if (!file.isFile) {
            callback.fail(PlayerError.FILE_NOT_FOUND, path)
            return@onMain
        }
        // Media3 would report a non-Ogg file only after the player exists; Darwin rejects it here too.
        val isOgg = try {
            file.hasOggSignature()
        } catch (e: IOException) {
            callback.fail(PlayerError.IO_ERROR, e.localizedMessage)
            return@onMain
        }
        if (!isOgg) {
            callback.fail(PlayerError.INVALID_FILE, "file is not an Ogg stream")
            return@onMain
        }
        registerPlayer(callback, OggOpusDuration.of(file)) { fileMediaSource(path) }
    }

    fun createFromUrl(url: String?, callback: CreateCallback) {
        if (url == null || !RemoteAudioLoader.isRemote(url)) {
            callback.fail(PlayerError.INVALID_ARGUMENT, "url must be an http or https URL")
            return
        }
        // The loader answers on the main thread.
        RemoteAudioLoader.load(url) { download ->
            if (!attached) {
                callback.fail(PlayerError.UNKNOWN, "Flutter engine detached before the download completed")
                return@load
            }
            download.fold(
                onSuccess = { bytes -> createFromBytes(bytes, callback) },
                onFailure = { error -> callback.fail(PlayerError.from(error), error.localizedMessage) },
            )
        }
    }

    fun createFromBytes(bytes: ByteArray?, callback: CreateCallback) = onMain {
        if (bytes == null || bytes.isEmpty()) {
            callback.fail(PlayerError.INVALID_ARGUMENT, "bytes must not be empty")
            return@onMain
        }
        if (!bytes.hasOggSignature()) {
            callback.fail(PlayerError.INVALID_FILE, "bytes are not an Ogg stream")
            return@onMain
        }
        registerPlayer(callback, OggOpusDuration.of(bytes)) { bytesMediaSource(bytes) }
    }

    private fun registerPlayer(callback: CreateCallback, duration: Double?, mediaSource: () -> MediaSource) {
        val id = try {
            val id = generateId()
            players[id] = AudioPlayer(context, mediaSource(), duration) { emitState(id, it) }
            id
        } catch (e: Exception) {
            callback.fail(PlayerError.from(e), e.localizedMessage)
            return
        }
        callback.onCreated(id)
    }

    fun play(playerId: Int) = onMain {
        val requested = players[playerId]
        // Like iOS, playback waits while a recording owns the microphone and the audio focus.
        if (requested != null && !recorders.isRecording) {
            // Audio focus is shared by the app. Also arbitrate its own players so two voice messages cannot overlap.
            players.values.toList().forEach { player ->
                if (player !== requested) player.pause()
            }
            requested.play()
        }
    }

    fun pause(playerId: Int) = onMain { players[playerId]?.pause() }

    fun stop(playerId: Int) = onMain { players.remove(playerId)?.destroy() }

    /** Waits for the source to be prepared; unknown only when the duration is really unavailable. */
    fun getDuration(playerId: Int, callback: OggRecordPlayerApi.DurationCallback) = onMain {
        val player = players[playerId]
        if (player == null) {
            callback.onDuration(false, 0.0)
        } else {
            player.awaitDuration { seconds -> callback.onDuration(seconds != null, seconds ?: 0.0) }
        }
    }

    fun setPlaybackSpeed(playerId: Int, speed: Double) = onMain {
        players[playerId]?.playbackRate = speed
    }

    fun createRecorder(path: String?): Int = if (path.isNullOrEmpty()) -1 else recorders.create(path)

    fun startRecord(recorderId: Int): String? {
        if (!recorders.hasRecordPermission()) return "PERMISSION_DENIED"
        onMain { recorders.start(recorderId) { players.values.toList().forEach { it.pause() } } }
        return null
    }

    fun stopRecord(recorderId: Int) = onMain { recorders.stop(recorderId) }

    fun destroyRecorder(recorderId: Int) = onMain { recorders.destroy(recorderId) }

    private fun emitState(id: Int, player: AudioPlayer) {
        if (!attached) return
        playerListener?.onStateChanged(
            id,
            player.state.ordinal,
            player.position,
            player.duration,
            player.playbackRate,
            // Set only when state is Failed, so Dart can tell why playback stopped.
            player.failure?.let { PlayerError.from(it).code },
        )
    }

    /** Called on the main thread when the engine detaches: releases everything and silences later events. */
    fun detach() {
        attached = false
        playerListener = null
        recorderListener = null
        players.values.toList().forEach { it.destroy() }
        players.clear()
        recorders.destroyAll()
    }
}

private fun CreateCallback.fail(playerError: PlayerError, details: String?) {
    onFailed(playerError.code, playerError.message, details)
}
