package uz.plugin.ogg_opus_player

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector

typealias OnPlayerStatusChangedCallback = (AudioPlayer) -> Unit

enum class Status {
    Initial,
    Playing,
    Paused,
    Stopped,
}

@UnstableApi
class AudioPlayer(
    context: Context,
    path: String,
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
        val mediaItem = MediaItem.fromUri(path)
        val datasource = ProgressiveMediaSource.Factory(DefaultDataSource.Factory(context))
            .createMediaSource(mediaItem)
        player.addListener(this)
        player.setMediaSource(datasource)
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
