@file:Suppress("DEPRECATION")

package uz.plugin.ogg_opus_player

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import java.io.File

class OpusAudioRecorder(
    ctx: Context,
    private val recordingAudioFile: File,
    private val callback: Callback? = null
) {
    companion object {
        private const val SAMPLE_RATE = 16000
        private const val BUFFER_SIZE_FACTOR = 2

        private const val STATE_NOT_INIT = 0
        const val STATE_IDLE = 1
        const val STATE_RECORDING = 2

        private const val MAX_RECORD_DURATION = 60000 * 3

        @Deprecated("Use instance state instead")
        var state: Int = STATE_NOT_INIT

        init {
            try {
                System.loadLibrary("ogg_opus_player_plugin")
            } catch (e: Exception) {
                e.printStackTrace()
            }
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

    private val recordSamples = ShortArray(1024)
    private var samplesCount = 0L
    private var recordTimeCount = 0L
    private var sendAfterDone = false
    @Volatile
    private var callStop = false
    @Volatile
    private var isStopping = false
    @Volatile
    private var isStopped = false
    @Volatile
    private var nativeHandle: Long = 0L

    var instanceState: Int = STATE_IDLE
        private set(value) {
            field = value
            state = value
        }

    private val recordQueueDelegate = lazy {
        DispatchQueue("recordQueue").apply {
            priority = Thread.MAX_PRIORITY
        }
    }
    private val recordQueue: DispatchQueue by recordQueueDelegate

    private val fileEncodingQueueDelegate = lazy {
        DispatchQueue("fileEncodingQueue").apply {
            priority = Thread.MAX_PRIORITY
        }
    }
    private val fileEncodingQueue: DispatchQueue by fileEncodingQueueDelegate

    /**
     * Stops both worker threads. Only quits queues that were actually started so a
     * failed start does not spin up the encoding thread just to tear it down.
     */
    private fun shutdownQueues() {
        if (fileEncodingQueueDelegate.isInitialized()) {
            fileEncodingQueue.quit()
        }
        if (recordQueueDelegate.isInitialized()) {
            recordQueue.quit()
        }
    }

    /**
     * Aborts a start that never reached STATE_RECORDING: marks the recorder dead,
     * notifies the caller and releases the worker threads so they are not leaked.
     * Must be called on recordQueue.
     */
    private fun failStart() {
        callStop = true
        isStopping = true
        isStopped = true
        instanceState = STATE_IDLE
        unregisterPhoneStateListener()
        mainHandler.post {
            callback?.onCancel()
        }
        shutdownQueues()
    }
    
    private val mainHandler = Handler(Looper.getMainLooper())

    private val telephonyManager =
        ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager?

    // Accessed on the main thread only.
    private var phoneStateListener: PhoneStateListener? = null

    private fun registerPhoneStateListener() {
        mainHandler.post {
            if (phoneStateListener != null) return@post
            try {
                val listener = object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, incomingNumber: String?) {
                        if (state != TelephonyManager.CALL_STATE_IDLE) {
                            stopRecording(AudioEndStatus.CANCEL)
                            callback?.onCancel()
                        }
                    }
                }
                telephonyManager?.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
                phoneStateListener = listener
            } catch (_: Exception) {
            }
        }
    }

    private fun unregisterPhoneStateListener() {
        mainHandler.post {
            val listener = phoneStateListener ?: return@post
            phoneStateListener = null
            try {
                telephonyManager?.listen(listener, PhoneStateListener.LISTEN_NONE)
            } catch (_: Exception) {
            }
        }
    }

    private val recordRunnable: Runnable by lazy {
        Runnable recordRunnable@{
            if (callStop || isStopping || isStopped) return@recordRunnable
            audioRecord?.let { audioRecord ->
                val shortArray = ShortArray(recordBufferSize)
                val len = audioRecord.read(shortArray, 0, shortArray.size)
                if (len > 0 && !callStop) {
                    var sum = 0
                    try {
                        val newSamplesCount = samplesCount + len
                        val currPart =
                            (samplesCount / newSamplesCount.toDouble() * recordSamples.size).toInt()
                        val newPart = recordSamples.size - currPart
                        var sampleStep: Float
                        if (currPart != 0) {
                            sampleStep = recordSamples.size / currPart.toFloat()
                            var currNum = 0f
                            for (i in 0 until currPart) {
                                recordSamples[i] = recordSamples[currNum.toInt()]
                                currNum += sampleStep
                            }
                        }
                        var currNum = currPart
                        var nextNum = 0f
                        sampleStep = if (newPart > 0) len.toFloat() / newPart else 0f
                        for (i in 0 until len) {
                            val peak = shortArray[i]
                            if (peak > 2500) {
                                sum += peak * peak
                            }
                            if (i == nextNum.toInt() && currNum < recordSamples.size) {
                                recordSamples[currNum] = peak
                                nextNum += sampleStep
                                currNum++
                            }
                        }
                        samplesCount = newSamplesCount
                    } catch (_: Exception) {
                    }

                    fileEncodingQueue.postRunnable(
                        Runnable encodingRunnable@{
                            if (callStop) return@encodingRunnable
                            val handle = nativeHandle
                            if (handle != 0L) {
                                writeFrame(handle, shortArray, len)
                                recordTimeCount += len / 16

                                if (recordTimeCount >= MAX_RECORD_DURATION) {
                                    stopRecording(AudioEndStatus.SEND)
                                }
                            }
                        }
                    )
                    if (!callStop && !isStopping && !isStopped) {
                        recordQueue.postRunnable(recordRunnable)
                    }
                } else {
                    if (!callStop && !isStopping && !isStopped) {
                        stopRecording(
                            if (sendAfterDone) {
                                AudioEndStatus.SEND
                            } else {
                                AudioEndStatus.CANCEL
                            }
                        )
                    }
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private val recodeStartRunnable = Runnable {
        if (audioRecord != null || isStopping || isStopped) {
            return@Runnable
        }

        if (recordingAudioFile.exists()) {
            recordingAudioFile.delete()
        }
        recordingAudioFile.createNewFile()
        try {
            val handle = startRecord(recordingAudioFile.absolutePath)
            if (handle == 0L) {
                recordingAudioFile.delete()
                failStart()
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

            if (audioRecord == null || audioRecord!!.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord?.release()
                audioRecord = null
                val h = nativeHandle
                nativeHandle = 0L
                if (h != 0L) stopRecord(h)
                recordingAudioFile.delete()
                failStart()
                return@Runnable
            }
            callStop = false
            samplesCount = 0
            recordTimeCount = 0
            audioRecord?.startRecording()

            if (audioRecord != null && audioRecord!!.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                val h = nativeHandle
                nativeHandle = 0L
                if (h != 0L) stopRecord(h)
                audioRecord?.release()
                audioRecord = null
                recordingAudioFile.delete()
                failStart()
                return@Runnable
            }
            instanceState = STATE_RECORDING
        } catch (e: Exception) {
            recordingAudioFile.delete()
            try {
                val h = nativeHandle
                nativeHandle = 0L
                if (h != 0L) stopRecord(h)
                audioRecord?.release()
                audioRecord = null
            } catch (ignore: Exception) {
            }
            failStart()
            return@Runnable
        }

        recordQueue.postRunnable(recordRunnable)
    }

    fun startRecording() {
        registerPhoneStateListener()
        recordQueue.postRunnable(recodeStartRunnable)
    }

    fun stopRecording(endStatus: AudioEndStatus) {
        if (isStopping) return
        isStopping = true
        callStop = true

        recordQueue.cancelRunnable(recodeStartRunnable)
        recordQueue.postRunnable(Runnable {
            val audioRecord = audioRecord
            if (audioRecord == null) {
                stopRecordingInternal(endStatus)
                return@Runnable
            }
            try {
                sendAfterDone = endStatus == AudioEndStatus.SEND
                if (audioRecord.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    audioRecord.stop()
                }
            } catch (e: Exception) {
                recordingAudioFile.delete()
            }
            stopRecordingInternal(endStatus)
        })
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
        unregisterPhoneStateListener()
        instanceState = STATE_IDLE

        // stopRecord() must run on fileEncodingQueue after all pending writeFrame
        // runnables, otherwise the native encoder is leaked and the file stays open.
        fileEncodingQueue.postRunnable(Runnable {
            val handle = nativeHandle
            nativeHandle = 0L
            if (handle != 0L) {
                stopRecord(handle)
            }
            if (endStatus == AudioEndStatus.CANCEL) {
                recordingAudioFile.delete()
            } else {
                val duration = recordTimeCount
                val waveForm = getWaveform2(recordSamples, recordSamples.size)
                mainHandler.post {
                    callback?.sendAudio(
                        recordingAudioFile,
                        duration,
                        waveForm
                    )
                }
            }
            // Shut down worker threads to avoid thread leaks
            shutdownQueues()
        })
    }

    private external fun startRecord(path: String): Long
    private external fun writeFrame(handle: Long, frame: ShortArray, len: Int): Int
    private external fun stopRecord(handle: Long)
    private external fun getWaveform2(arr: ShortArray, len: Int): ByteArray

    interface Callback {
        fun onCancel()
        fun sendAudio(file: File, duration: Long, waveForm: ByteArray)
    }
}
