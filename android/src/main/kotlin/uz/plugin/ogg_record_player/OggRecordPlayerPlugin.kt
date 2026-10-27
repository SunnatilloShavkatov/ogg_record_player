package uz.plugin.ogg_record_player

import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.MediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.IOException
import java.util.Collections
import kotlin.concurrent.thread

/** OggRecordPlayerPlugin */
class OggRecordPlayerPlugin : FlutterPlugin, MethodCallHandler {

    companion object {

        private var lastGeneratedId = 0

        @Synchronized
        private fun generatePlayerId(): Int {
            lastGeneratedId++
            return lastGeneratedId
        }

    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var attached = false
    private var engineGeneration = 0

    private val mainHandler = Handler(Looper.getMainLooper())

    private val players: MutableMap<Int, AudioPlayer> = Collections.synchronizedMap(mutableMapOf())
    private val recorders: MutableMap<Int, OpusAudioRecorder> = Collections.synchronizedMap(mutableMapOf())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        attached = true
        engineGeneration++
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ogg_record_player")
        channel.setMethodCallHandler(this)
    }

    // Same checks as Darwin, so both platforms report a missing file the same way instead of an idle player.
    @OptIn(UnstableApi::class)
    private fun createFromFile(path: String, result: Result) {
        val file = File(path)
        if (!file.isFile) {
            result.fail(PlayerError.FILE_NOT_FOUND, path)
            return
        }
        // Media3 would report a non-Ogg file only after the player exists; Darwin rejects it here too.
        val isOgg = try {
            file.hasOggSignature()
        } catch (e: IOException) {
            result.fail(PlayerError.IO_ERROR, e.localizedMessage)
            return
        }
        if (!isOgg) {
            result.fail(PlayerError.INVALID_FILE, "file is not an Ogg stream")
            return
        }
        registerPlayer(result) { fileMediaSource(path) }
    }

    private fun createFromUrl(url: String, result: Result) {
        val requestGeneration = engineGeneration
        RemoteAudioLoader.load(url) { download ->
            if (!attached || engineGeneration != requestGeneration) {
                result.fail(PlayerError.UNKNOWN, "Flutter engine detached before the download completed")
                return@load
            }
            download.fold(
                onSuccess = { bytes -> createFromBytes(bytes, result) },
                onFailure = { error -> result.fail(PlayerError.from(error), error.localizedMessage) },
            )
        }
    }

    @OptIn(UnstableApi::class)
    private fun createFromBytes(bytes: ByteArray, result: Result) {
        if (!bytes.hasOggSignature()) {
            result.fail(PlayerError.INVALID_FILE, "bytes are not an Ogg stream")
            return
        }
        registerPlayer(result) { bytesMediaSource(bytes) }
    }

    @OptIn(UnstableApi::class)
    private fun registerPlayer(result: Result, mediaSource: () -> MediaSource) {
        try {
            val id = generatePlayerId()
            players[id] = AudioPlayer(context, mediaSource()) { handlePlayerStateChanged(id, it) }
            result.success(id)
        } catch (e: Exception) {
            result.fail(PlayerError.from(e), e.localizedMessage)
        }
    }

    /**
     * A cold first player spends part of its setup on Media3 listing the device's Opus decoders. The list is cached
     * process-wide, so querying it here off main lets the first real player skip it. Audio focus is untouched.
     */
    @OptIn(UnstableApi::class)
    private fun warmUp(result: Result) {
        thread(name = "ogg_record_player.warmUp", isDaemon = true) {
            runCatching { MediaCodecUtil.getDecoderInfos(MimeTypes.AUDIO_OPUS, false, false) }
            mainHandler.post { result.success(null) }
        }
    }

    @OptIn(UnstableApi::class)
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "createFromFile" -> {
                val path = call.arguments as? String
                if (path.isNullOrEmpty()) {
                    result.fail(PlayerError.INVALID_ARGUMENT, "path must be a non-empty string")
                    return
                }
                createFromFile(path, result)
            }

            "createFromUrl" -> {
                val url = call.arguments as? String
                if (url == null || !RemoteAudioLoader.isRemote(url)) {
                    result.fail(PlayerError.INVALID_ARGUMENT, "url must be an http or https URL")
                    return
                }
                createFromUrl(url, result)
            }

            "createFromBytes" -> {
                val bytes = call.arguments as? ByteArray
                if (bytes == null || bytes.isEmpty()) {
                    result.fail(PlayerError.INVALID_ARGUMENT, "bytes must not be empty")
                    return
                }
                createFromBytes(bytes, result)
            }

            "warmUp" -> warmUp(result)

            "play" -> {
                (call.arguments as? Int)?.let {
                    val requested = players[it]
                    if (requested != null) {
                        // Audio focus is shared by the app. Also arbitrate its own
                        // players so two voice messages cannot overlap.
                        players.values.toList().forEach { player ->
                            if (player !== requested) player.pause()
                        }
                        requested.play()
                    }
                }
                result.success(null)
            }

            "getDuration" -> {
                // Waits for the source to be prepared; null only when the duration is really unavailable.
                val player = (call.arguments as? Int)?.let { players[it] }
                if (player == null) {
                    result.success(null)
                } else {
                    player.awaitDuration { result.success(it) }
                }
            }

            "pause" -> {
                (call.arguments as? Int)?.let {
                    players[it]?.pause()
                }
                result.success(null)
            }

            "stop" -> {
                (call.arguments as? Int)?.let {
                    players.remove(it)?.destroy()
                }
                result.success(null)
            }

            "setPlaybackSpeed" -> {
                val playerId = call.argument<Int>("playerId")
                val speed = call.argument<Double>("speed")
                val player = players[playerId]
                if (player != null && speed != null) {
                    player.playbackRate = speed
                }
                result.success(null)
            }

            "createRecorder" -> {
                val path = call.arguments as? String
                if (path.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "recorder path must be a non-empty string", null)
                    return
                }
                val id = generatePlayerId()
                val requestGeneration = engineGeneration
                val recorder =
                    OpusAudioRecorder(context, File(path), object : OpusAudioRecorder.Callback {
                        override fun onCancel(reason: Int) {
                            if (!attached || engineGeneration != requestGeneration) return
                            channel.invokeMethod(
                                "onRecorderCanceled", mapOf(
                                    "recorderId" to id,
                                    "reason" to reason,
                                )
                            )
                        }

                        override fun onStartFailed(message: String) {
                            if (!attached || engineGeneration != requestGeneration) return
                            channel.invokeMethod(
                                "onRecorderStartFailed", mapOf(
                                    "recorderId" to id,
                                    "error" to message,
                                )
                            )
                        }

                        override fun sendAudio(file: File, duration: Long, waveForm: ByteArray) {
                            if (!attached || engineGeneration != requestGeneration) return
                            channel.invokeMethod(
                                "onRecorderFinished", mapOf(
                                    "recorderId" to id,
                                    "duration" to duration,
                                    "waveform" to waveForm,
                                )
                            )
                        }
                    })
                recorders[id] = recorder
                result.success(id)
            }

            "startRecord" -> {
                // check has permission
                val hasPermission =
                    context.checkCallingOrSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                if (hasPermission == PackageManager.PERMISSION_DENIED) {
                    result.error("PERMISSION_DENIED", "RECORD_AUDIO", null)
                    return
                }
                (call.arguments as? Int)?.let {
                    val recorder = recorders[it]
                    if (recorder != null) {
                        players.values.toList().forEach { player -> player.pause() }
                        recorder.startRecording()
                    }
                }
                result.success(null)
            }

            "stopRecord" -> {
                (call.arguments as? Int)?.let {
                    recorders[it]?.stopRecording(AudioEndStatus.SEND)
                    recorders.remove(it)
                }
                result.success(null)
            }

            "destroyRecorder" -> {
                (call.arguments as? Int)?.let {
                    recorders[it]?.stopRecording(AudioEndStatus.CANCEL)
                    recorders.remove(it)
                }
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    @OptIn(UnstableApi::class)
    private fun handlePlayerStateChanged(id: Int, player: AudioPlayer) {
        channel.invokeMethod(
            "onPlayerStateChanged", mapOf(
                "state" to player.state.ordinal,
                "playerId" to id,
                "position" to player.position,
                "duration" to player.duration,
                "speed" to player.playbackRate,
                // Set only when state is Failed, so Dart can tell why playback stopped.
                "errorCode" to player.failure?.let { PlayerError.from(it).code },
            )
        )
    }

    @OptIn(UnstableApi::class)
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        engineGeneration++
        channel.setMethodCallHandler(null)
        players.values.toList().forEach { it.destroy() }
        players.clear()
        recorders.values.toList().forEach { it.stopRecording(AudioEndStatus.CANCEL) }
        recorders.clear()
    }
}
