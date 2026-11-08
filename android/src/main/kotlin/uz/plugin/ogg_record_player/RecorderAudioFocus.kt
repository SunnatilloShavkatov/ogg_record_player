package uz.plugin.ogg_record_player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler

/**
 * Holds `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` for the duration of a recording. A call, an assistant or another
 * recording app taking the focus calls [onLost], which ends the recording like an iOS session interruption.
 * Ducking requests (navigation prompts, notifications) do not. Needs no permission.
 */
internal class RecorderAudioFocus(
    ctx: Context,
    handler: Handler,
    onLost: () -> Unit
) {
    private val audioManager = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager?

    private val focusRequest: AudioFocusRequest =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setOnAudioFocusChangeListener({ change ->
                if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                    onLost()
                }
            }, handler)
            .build()

    /** Fails during a phone call, so a recording cannot start while the microphone belongs to the call. */
    fun request(): Boolean {
        val manager = audioManager ?: return true
        return manager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    fun abandon() {
        runCatching { audioManager?.abandonAudioFocusRequest(focusRequest) }
    }
}
