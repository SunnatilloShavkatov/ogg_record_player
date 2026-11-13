package uz.plugin.ogg_record_player

import android.content.Context
import android.content.pm.PackageManager
import java.io.File
import java.util.Collections

/**
 * The Dart recorders of one engine, by id. Native sessions are created per `startRecord`; [events] is the
 * engine's host, which drops them once the engine detached.
 */
internal class RecorderRegistry(
    private val context: Context,
    private val generateId: () -> Int,
    private val events: OggRecordPlayerApi.RecorderListener,
) {
    /**
     * One Dart recorder. Its file and callback live as long as the recorder; every `startRecord` records a fresh
     * native session into the file, so the same recorder can record again after `stopRecord`.
     */
    private class RecorderSlot(val file: File, val callback: OpusAudioRecorder.Callback) {
        var session: OpusAudioRecorder? = null
    }

    private val slots: MutableMap<Int, RecorderSlot> = Collections.synchronizedMap(mutableMapOf())

    val isRecording: Boolean get() = slots.values.toList().any { it.session?.isActive == true }

    fun hasRecordPermission(): Boolean =
        context.checkCallingOrSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_DENIED

    fun create(path: String): Int {
        val id = generateId()
        val callback = object : OpusAudioRecorder.Callback {
            override fun onCancel(reason: Int) = events.onCanceled(id, reason)

            override fun onStartFailed(message: String) = events.onStartFailed(id, message)

            override fun sendAudio(file: File, duration: Long, waveForm: ByteArray) =
                events.onFinished(id, duration, waveForm)
        }
        slots[id] = RecorderSlot(File(path), callback)
        return id
    }

    /** A second start while recording is ignored; once stopped, a new session records again. */
    fun start(id: Int, beforeStart: () -> Unit) {
        val slot = slots[id] ?: return
        if (slot.session?.isActive == true) return
        beforeStart()
        slot.session = OpusAudioRecorder(context, slot.file, slot.callback).also { it.startRecording() }
    }

    fun stop(id: Int) {
        slots[id]?.session?.stopRecording(AudioEndStatus.SEND)
    }

    fun destroy(id: Int) {
        slots.remove(id)?.session?.stopRecording(AudioEndStatus.CANCEL)
    }

    fun destroyAll() {
        slots.values.toList().forEach { it.session?.stopRecording(AudioEndStatus.CANCEL) }
        slots.clear()
    }
}
