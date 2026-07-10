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

    private var recordBufferSize: Int = AudioRecord.getMinBufferSize(
        SAMPLE_RATE,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT
    )

    private val recordSamples = ShortArray(1024)
    private var samplesCount = 0L
    private var recordTimeCount = 0L
    private var sendAfterDone = false
    private var callStop = false


    private val recordQueue: DispatchQueue by lazy {
        DispatchQueue("recordQueue").apply {
            priority = Thread.MAX_PRIORITY
        }
    }
    private val fileEncodingQueue: DispatchQueue by lazy {
        DispatchQueue("fileEncodingQueue").apply {
            priority = Thread.MAX_PRIORITY
        }
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
                        sampleStep = len.toFloat() / newPart
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

                            writeFrame(shortArray, len)
                            recordTimeCount += len / 16

                            if (recordTimeCount >= MAX_RECORD_DURATION) {
                                stopRecording(AudioEndStatus.SEND)
                            }
                        }
                    )
                    recordQueue.postRunnable(recordRunnable)
                } else {
                    stopRecordingInternal(
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

    @SuppressLint("MissingPermission")
    private val recodeStartRunnable = Runnable {
        if (audioRecord != null) {
            return@Runnable
        }

        if (recordingAudioFile.exists()) {
            recordingAudioFile.delete()
        }
        recordingAudioFile.createNewFile()
        try {
            if (startRecord(recordingAudioFile.absolutePath) != 0) {
                unregisterPhoneStateListener()
                return@Runnable
            }

            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                recordBufferSize * BUFFER_SIZE_FACTOR
            )

            if (audioRecord == null || audioRecord!!.state != AudioRecord.STATE_INITIALIZED) {
                unregisterPhoneStateListener()
                return@Runnable
            }
            callStop = false
            samplesCount = 0
            recordTimeCount = 0
            audioRecord?.startRecording()

            if (audioRecord != null && audioRecord!!.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                audioRecord?.release()
                audioRecord = null
                unregisterPhoneStateListener()
                return@Runnable
            }
            state = STATE_RECORDING
        } catch (e: Exception) {
            recordingAudioFile.delete()
            try {
                stopRecord()
                state = STATE_IDLE
                audioRecord?.release()
                audioRecord = null
            } catch (ignore: Exception) {
            }
            unregisterPhoneStateListener()
            return@Runnable
        }

        recordQueue.postRunnable(recordRunnable)
    }

    fun startRecording() {
        registerPhoneStateListener()
        recordQueue.postRunnable(recodeStartRunnable)
    }

    fun stopRecording(endStatus: AudioEndStatus) {
        recordQueue.cancelRunnable(recodeStartRunnable)
        recordQueue.postRunnable(
            {
                val audioRecord = audioRecord
                if (audioRecord == null) {
                    unregisterPhoneStateListener()
                    return@postRunnable
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
            }
        )
    }

    private fun stopRecordingInternal(endStatus: AudioEndStatus) {
        callStop = true
        // stopRecord() must run on fileEncodingQueue after all pending writeFrame
        // runnables, otherwise the native encoder is leaked and the file stays open.
        fileEncodingQueue.postRunnable(
            {
                stopRecord()
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
            }
        )
        state = STATE_IDLE
        try {
            audioRecord?.release()
            audioRecord = null
        } catch (ignore: Exception) {
        }
        unregisterPhoneStateListener()
    }

    private external fun startRecord(path: String): Int
    private external fun writeFrame(frame: ShortArray, len: Int): Int
    private external fun stopRecord()
    private external fun getWaveform2(arr: ShortArray, len: Int): ByteArray

    interface Callback {
        fun onCancel()
        fun sendAudio(file: File, duration: Long, waveForm: ByteArray)
    }
}
