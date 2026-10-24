package uz.plugin.ogg_opus_player

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
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import java.io.File

typealias OnPlayerStatusChangedCallback = (AudioPlayer) -> Unit

/** Plays a local file (also used for cached downloads). */
@UnstableApi
internal fun fileMediaSource(context: Context, path: String): MediaSource =
    ProgressiveMediaSource.Factory(DefaultDataSource.Factory(context))
        .createMediaSource(MediaItem.fromUri(Uri.fromFile(File(path))))

/** Plays an Ogg Opus stream held in memory, e.g. bytes received from a backend, without a temporary file. */
@UnstableApi
internal fun bytesMediaSource(bytes: ByteArray): MediaSource =
    ProgressiveMediaSource.Factory(DataSource.Factory { ByteArrayDataSource(bytes) })
        .createMediaSource(MediaItem.fromUri(Uri.parse("memory://ogg_record_player")))

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

    // ExoPlayer takes audio focus when playback starts and gives it up when it pauses or ends. Losing the focus
    // pauses the player (`playWhenReady` becomes false) or, for a transient loss, suppresses playback.
    private val player = ExoPlayer.Builder(context)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(),
            true
        )
        .setTrackSelector(DefaultTrackSelector(context)).build().apply {
            volume = 1.0f
        }

    val position: Int get() = player.currentPosition.toInt() / 1000

    val duration: Int get() = player.duration.toInt() / 1000

    val state: Status
        get() {
            when (player.playbackState) {
                Player.STATE_IDLE -> {
                    return Status.Initial
                }

                Player.STATE_READY -> {
                    // A transient focus loss (for example a call) keeps `playWhenReady` true but silences the player.
                    return if (player.playWhenReady &&
                        player.playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE
                    ) {
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

    private var _playbackRate: Double = 1.0
    var playbackRate: Double
        set(value) {
            _playbackRate = value
            player.setPlaybackSpeed(value.toFloat())
        }
        get() = _playbackRate


    init {
        player.addListener(this)
        player.setMediaSource(mediaSource)
        player.prepare()
    }

    fun play() {
        player.playWhenReady = true
    }

    fun pause() {
        player.playWhenReady = false
    }

    fun destroy() {
        player.stop()
        player.removeListener(this)
        player.release()
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        callback(this)
    }

    override fun onPlaybackSuppressionReasonChanged(playbackSuppressionReason: Int) {
        callback(this)
    }

    override fun onPlayerError(error: PlaybackException) {
        callback(this)
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
            player.playWhenReady = false
            callback(this)
        } else {
            callback(this)
        }
    }
}
