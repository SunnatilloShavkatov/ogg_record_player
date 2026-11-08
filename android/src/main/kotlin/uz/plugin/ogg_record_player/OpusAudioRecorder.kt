package uz.plugin.ogg_record_player

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue

class OpusAudioRecorder(
    ctx: Context,
    private val recordingAudioFile: File,
    private val callback: Callback? = null
) {
    companion object {
        private const val SAMPLE_RATE = 16000
        private const val BUFFER_SIZE_FACTOR = 2

        const val STATE_IDLE = 1
        const val STATE_RECORDING = 2

        private const val MAX_RECORD_DURATION = 60000 * 3

        // Same values as Darwin's `OggOpusRecorder.CancelledReason`, which Dart receives as `reason`.
        const val CANCEL_AUDIO_SESSION_INTERRUPTED = 0
        const val CANCEL_BUFFER_FAILED = 2
        const val CANCEL_UNUSABLE_RECORDING = 4

        init {
            runCatching { System.loadLibrary("ogg_record_player_plugin") }
        }
    }

    private var audioRecord: AudioRecord? = null

    private var recordBufferSize: Int = maxOf(
        AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ),
        1024
    )

    private val waveformSampler = WaveformSampler()

    // Read buffers travel to the encoding thread; it hands them back here instead of leaving them to the GC.
    private val bufferPool = ConcurrentLinkedQueue<ShortArray>()
    private var recordTimeCount = 0L
    @Volatile private var callStop = false
    @Volatile private var isStopping = false
    @Volatile private var isStopped = false
    @Volatile private var nativeHandle: Long = 0L

    var instanceState: Int = STATE_IDLE
        private set

    private val queues = RecorderQueues()

    private val isRunning: Boolean get() = !callStop && !isStopping && !isStopped

    /**
     * Aborts a start that never reached STATE_RECORDING: marks the recorder dead,
     * reports [message] as a start failure (Dart's `startError`) and releases the
     * worker threads so they are not leaked. Must be called on recordQueue.
     */
    private fun failStart(message: String) {
        callStop = true
        isStopping = true
        isStopped = true
        instanceState = STATE_IDLE
        audioFocus.abandon()
        mainHandler.post {
            callback?.onStartFailed(message)
        }
        queues.shutdown()
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // Losing the focus ends the recording; only the loss that actually does reports it, a stop already underway
    // answers itself.
    private val audioFocus = RecorderAudioFocus(ctx, mainHandler) {
        if (stopRecording(AudioEndStatus.CANCEL)) {
            callback?.onCancel(CANCEL_AUDIO_SESSION_INTERRUPTED)
        }
    }

    private val recordRunnable: Runnable by lazy {
        Runnable recordRunnable@{
            if (!isRunning) return@recordRunnable
            audioRecord?.let { audioRecord ->
                val shortArray = bufferPool.poll() ?: ShortArray(recordBufferSize)
                val len = audioRecord.read(shortArray, 0, shortArray.size)
                if (len > 0 && !callStop) {
                    waveformSampler.add(shortArray, len)

                    queues.fileEncoding.postRunnable(
                        Runnable encodingRunnable@{
                            if (callStop) return@encodingRunnable
                            val handle = nativeHandle
                            if (handle != 0L) {
                                val written = writeFrame(handle, shortArray, len)
                                bufferPool.offer(shortArray)
                                if (written != 0) {
                                    // The encoder rejected audio (e.g. the disk is full): the file would be cut short.
                                    cancelUnusable()
                                    return@encodingRunnable
                                }
                                recordTimeCount += len / 16

                                if (recordTimeCount >= MAX_RECORD_DURATION) {
                                    stopRecording(AudioEndStatus.SEND)
                                }
                            }
                        }
                    )
                    if (isRunning) {
                        queues.record.postRunnable(recordRunnable)
                    }
                } else if (isRunning) {
                    // The microphone stopped delivering audio (e.g. taken by another app). Nothing else
                    // reports this, so Dart's stop() would wait for an event that never comes.
                    stopRecording(AudioEndStatus.CANCEL)
                    mainHandler.post { callback?.onCancel(CANCEL_BUFFER_FAILED) }
                }
            }
        }
    }

    private fun closeNativeEncoder() {
        val handle = nativeHandle
        nativeHandle = 0L
        if (handle != 0L) stopRecord(handle)
    }

    /** Releases whatever a failed start had already opened, drops the partial file and reports [message]. */
    private fun abortStart(message: String) {
        runCatching {
            closeNativeEncoder()
            audioRecord?.release()
        }
        audioRecord = null
        recordingAudioFile.delete()
        failStart(message)
    }

    @SuppressLint("MissingPermission")
    private val recodeStartRunnable = Runnable {
        if (audioRecord != null || isStopping || isStopped) {
            return@Runnable
        }

        if (!audioFocus.request()) {
            failStart("The audio focus is held by a call or another app")
            return@Runnable
        }

        try {
            // Inside the try: a missing or unwritable directory throws here, and an exception escaping
            // this runnable would kill the app from the worker thread.
            if (recordingAudioFile.exists()) {
                recordingAudioFile.delete()
            }
            recordingAudioFile.createNewFile()
            val handle = startRecord(recordingAudioFile.absolutePath)
            if (handle == 0L) {
                abortStart("Could not open ${recordingAudioFile.name} for writing")
                return@Runnable
            }
            nativeHandle = handle

            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                recordBufferSize * BUFFER_SIZE_FACTOR
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                abortStart("The microphone could not be initialized")
                return@Runnable
            }
            callStop = false
            waveformSampler.reset()
            recordTimeCount = 0
            audioRecord?.startRecording()

            if (audioRecord?.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                abortStart("The microphone is in use by another app")
                return@Runnable
            }
            instanceState = STATE_RECORDING
        } catch (e: Exception) {
            abortStart(e.localizedMessage ?: "Recording could not be started")
            return@Runnable
        }

        queues.record.postRunnable(recordRunnable)
    }

    /** `false` once a stop was requested; a new recording then needs a new instance. */
    val isActive: Boolean get() = !isStopping

    fun startRecording() {
        queues.record.postRunnable(recodeStartRunnable)
    }

    /** Reports an unusable file as a cancel, unless a stop is already underway and will report its own outcome. */
    private fun cancelUnusable() {
        if (stopRecording(AudioEndStatus.CANCEL)) {
            mainHandler.post { callback?.onCancel(CANCEL_UNUSABLE_RECORDING) }
        }
    }

    /** Returns `false` when a stop was already requested, so the caller must not report a second outcome. */
    fun stopRecording(endStatus: AudioEndStatus): Boolean {
        if (isStopping) return false
        isStopping = true
        callStop = true

        queues.record.cancelRunnable(recodeStartRunnable)
        queues.record.postRunnable(Runnable {
            val audioRecord = audioRecord
            if (audioRecord == null) {
                stopRecordingInternal(endStatus)
                return@Runnable
            }
            try {
                if (audioRecord.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    audioRecord.stop()
                }
            } catch (e: Exception) {
                recordingAudioFile.delete()
            }
            stopRecordingInternal(endStatus)
        })
        return true
    }

    private fun stopRecordingInternal(endStatus: AudioEndStatus) {
        if (isStopped) return
        isStopped = true
        callStop = true

        try {
            audioRecord?.release()
            audioRecord = null
        } catch (ignore: Exception) {
        }
        audioFocus.abandon()
        instanceState = STATE_IDLE

        // recordSamples is written on recordQueue (where this runs), so read a snapshot on the other thread.
        val waveformSamples = waveformSampler.snapshot()

        // stopRecord() must run on fileEncodingQueue after all pending writeFrame
        // runnables, otherwise the native encoder is leaked and the file stays open.
        queues.fileEncoding.postRunnable(Runnable {
            val handle = nativeHandle
            nativeHandle = 0L
            // False for a recording too short to form a valid stream, or one with write errors.
            val finalized = handle != 0L && stopRecord(handle)
            if (endStatus == AudioEndStatus.CANCEL) {
                recordingAudioFile.delete()
            } else if (!finalized) {
                recordingAudioFile.delete()
                mainHandler.post { callback?.onCancel(CANCEL_UNUSABLE_RECORDING) }
            } else {
                val duration = recordTimeCount
                val waveForm = getWaveform2(waveformSamples, waveformSamples.size)
                mainHandler.post {
                    callback?.sendAudio(
                        recordingAudioFile,
                        duration,
                        waveForm
                    )
                }
            }
            // Shut down worker threads to avoid thread leaks
            queues.shutdown()
        })
    }

    private external fun startRecord(path: String): Long
    private external fun writeFrame(handle: Long, frame: ShortArray, len: Int): Int
    private external fun stopRecord(handle: Long): Boolean
    private external fun getWaveform2(arr: ShortArray, len: Int): ByteArray

    interface Callback {
        fun onCancel(reason: Int)
        fun onStartFailed(message: String)
        fun sendAudio(file: File, duration: Long, waveForm: ByteArray)
    }
}
