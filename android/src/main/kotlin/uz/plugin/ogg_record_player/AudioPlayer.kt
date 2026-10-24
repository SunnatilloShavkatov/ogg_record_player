package uz.plugin.ogg_record_player

import android.content.Context
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
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
}

@UnstableApi
class AudioPlayer(
    context: Context,
    mediaSource: MediaSource,
    private val callback: OnPlayerStatusChangedCallback,
) : Player.Listener {

    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
        .build()
    private var focusEnabled = true

    // Media3 handles transient loss/resumption (including calls) on its playback
    // thread. Manual pauses/end release focus without discarding the prepared source.
    private val player = ExoPlayer.Builder(context, audioRenderersFactory(context), MediaSource.Factory.UNSUPPORTED)
        .setAudioAttributes(audioAttributes, true)
        .setTrackSelector(DefaultTrackSelector(context)).build().apply {
            volume = 1.0f
        }

    val position: Double get() = player.currentPosition / 1000.0

    val duration: Double get() = if (player.duration == C.TIME_UNSET) 0.0 else player.duration / 1000.0

    val state: Status
        get() {
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
                player.setPlaybackSpeed(value.coerceIn(0.5, 2.0).toFloat())
            }
        }
        get() = player.playbackParameters.speed.toDouble()


    init {
        player.addListener(this)
        player.setMediaSource(mediaSource)
        player.prepare()
    }

    fun play() {
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
        player.pause()
        releaseAudioFocus()
    }

    private fun releaseAudioFocus() {
        if (focusEnabled) {
            focusEnabled = false
            player.setAudioAttributes(audioAttributes, false)
        }
    }

    fun destroy() {
        player.removeListener(this)
        player.release()
    }

    // One coherent snapshot after a batch of events, including buffering, focus suppression,
    // metadata and speed changes. Never rewind before reporting the final position.
    override fun onEvents(player: Player, events: Player.Events) {
        if (player.playbackState == Player.STATE_ENDED) {
            releaseAudioFocus()
        }
        callback(this)
    }
}
