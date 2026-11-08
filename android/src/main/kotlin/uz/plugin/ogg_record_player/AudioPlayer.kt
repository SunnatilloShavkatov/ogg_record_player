package uz.plugin.ogg_record_player

import android.content.Context
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.FileDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.audio.MediaCodecAudioRenderer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ogg.OggExtractor
import java.io.File

typealias OnPlayerStatusChangedCallback = (AudioPlayer) -> Unit

/** Plays a local file. */
@UnstableApi
internal fun fileMediaSource(path: String): MediaSource =
    ProgressiveMediaSource.Factory(FileDataSource.Factory(), oggExtractorsFactory())
        .createMediaSource(MediaItem.fromUri(Uri.fromFile(File(path))))

/** Plays an Ogg Opus stream held in memory, e.g. bytes received from a backend, without a temporary file. */
@UnstableApi
internal fun bytesMediaSource(bytes: ByteArray): MediaSource =
    ProgressiveMediaSource.Factory(DataSource.Factory { ByteArrayDataSource(bytes) }, oggExtractorsFactory())
        .createMediaSource(MediaItem.fromUri(Uri.parse("memory://ogg_record_player")))

@UnstableApi
private fun oggExtractorsFactory() = ExtractorsFactory { arrayOf<Extractor>(OggExtractor()) }

// Avoid retaining video, subtitle and metadata renderers in release builds that use R8.
@UnstableApi
private fun audioRenderersFactory(context: Context) = RenderersFactory { handler, _, audioListener, _, _ ->
    arrayOf<Renderer>(MediaCodecAudioRenderer(context, MediaCodecSelector.DEFAULT, handler, audioListener))
}

enum class Status {
    Initial,
    Playing,
    Paused,
    Stopped,

    /** Playback failed after the player was created; mapped to `PlayerState.error` in Dart. */
    Failed,
}

/**
 * One voice message. The ExoPlayer (a playback thread, a decoder and an AudioTrack) is created only when the
 * message is played, or when its duration cannot be read from the container; a chat with many messages therefore
 * does not hold one decoder per message.
 */
@UnstableApi
class AudioPlayer(
    private val context: Context,
    private val mediaSource: MediaSource,
    /** Duration read from the Ogg container ([OggOpusDuration]), or `null` when only the decoder can tell. */
    private val containerDuration: Double?,
    private val callback: OnPlayerStatusChangedCallback,
) : Player.Listener {

    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
        .build()
    private var focusEnabled = true
    private var speed = 1.0

    private var exoPlayer: ExoPlayer? = null

    // Media3 handles transient loss/resumption (including calls) on its playback
    // thread. Manual pauses/end release focus without discarding the prepared source.
    private fun player(): ExoPlayer = exoPlayer ?: ExoPlayer.Builder(
        context,
        audioRenderersFactory(context),
        MediaSource.Factory.UNSUPPORTED,
    )
        .setAudioAttributes(audioAttributes, focusEnabled)
        .setTrackSelector(DefaultTrackSelector(context)).build().apply {
            volume = 1.0f
            setPlaybackSpeed(speed.toFloat())
            addListener(this@AudioPlayer)
            setMediaSource(mediaSource)
            prepare()
        }.also { exoPlayer = it }

    val position: Double get() = (exoPlayer?.currentPosition ?: 0L) / 1000.0

    /** Total duration in seconds, or `null` while the source is unprepared or does not report one. */
    val durationOrNull: Double?
        get() {
            val duration = exoPlayer?.duration ?: C.TIME_UNSET
            return if (duration == C.TIME_UNSET) containerDuration else duration / 1000.0
        }

    /** [durationOrNull] for the state callback payload, which has no way to say "unknown". */
    val duration: Double get() = durationOrNull ?: 0.0

    /** The error that stopped playback, kept so [state] keeps reporting [Status.Failed] afterwards. */
    var failure: PlaybackException? = null
        private set

    private var released = false
    private val durationWaiters = mutableListOf<(Double?) -> Unit>()

    val state: Status
        get() {
            if (failure != null) {
                return Status.Failed
            }
            val player = exoPlayer ?: return Status.Paused
            when (player.playbackState) {
                Player.STATE_IDLE -> {
                    return Status.Initial
                }

                Player.STATE_READY -> {
                    // A transient focus loss (for example a call) keeps `playWhenReady` true but silences the player.
                    return if (player.isPlaying) {
                        Status.Playing
                    } else {
                        Status.Paused
                    }
                }

                Player.STATE_ENDED -> {
                    return Status.Stopped
                }

                else -> return Status.Paused
            }
        }

    var playbackRate: Double
        set(value) {
            if (value.isFinite()) {
                speed = value.coerceIn(0.5, 2.0)
                exoPlayer?.setPlaybackSpeed(speed.toFloat())
            }
        }
        get() = speed

    fun play() {
        if (released) return
        val player = player()
        if (!focusEnabled) {
            focusEnabled = true
            player.setAudioAttributes(audioAttributes, true)
        }
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
        }
        player.play()
    }

    fun pause() {
        val player = exoPlayer ?: return
        player.pause()
        releaseAudioFocus()
    }

    private fun releaseAudioFocus() {
        if (focusEnabled) {
            focusEnabled = false
            exoPlayer?.setAudioAttributes(audioAttributes, false)
        }
    }

    /**
     * Calls [onResult] on the main thread with the duration once it is known. Unlike [durationOrNull], it does
     * not answer `null` just because preparing has not finished: `null` means the duration is unavailable
     * (unknown length, playback failure or destroyed player).
     */
    fun awaitDuration(onResult: (Double?) -> Unit) {
        if (released || failure != null || durationSettled()) {
            onResult(if (released) null else durationOrNull)
            return
        }
        durationWaiters.add(onResult)
        // The container did not tell; only a prepared player can. Preparing does not start playback or take focus.
        player()
    }

    private fun durationSettled(): Boolean {
        val player = exoPlayer ?: return containerDuration != null
        return durationOrNull != null || player.playbackState == Player.STATE_READY ||
            player.playbackState == Player.STATE_ENDED
    }

    private fun flushDurationWaiters(duration: Double?) {
        val waiters = durationWaiters.toList()
        durationWaiters.clear()
        waiters.forEach { it(duration) }
    }

    fun destroy() {
        released = true
        flushDurationWaiters(null)
        exoPlayer?.let {
            it.removeListener(this)
            it.release()
        }
        exoPlayer = null
    }

    override fun onPlayerError(error: PlaybackException) {
        failure = error
    }

    // One coherent snapshot after a batch of events, including buffering, focus suppression,
    // metadata and speed changes. Never rewind before reporting the final position.
    override fun onEvents(player: Player, events: Player.Events) {
        if (player.playbackState == Player.STATE_ENDED) {
            releaseAudioFocus()
        }
        if (durationWaiters.isNotEmpty() && (failure != null || durationSettled())) {
            flushDurationWaiters(durationOrNull)
        }
        callback(this)
    }
}
