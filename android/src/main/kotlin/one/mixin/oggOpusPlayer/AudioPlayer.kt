package one.mixin.oggOpusPlayer

import android.content.Context
import android.util.Log
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

    companion object {
        private const val TAG = "AudioPlayer"
    }

    private val player = ExoPlayer.Builder(context)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(),
            false
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
                    return if (player.playWhenReady) {
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
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        Log.d(TAG, "onPlayWhenReadyChanged: $playWhenReady $reason")
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