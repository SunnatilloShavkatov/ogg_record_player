package uz.plugin.ogg_record_player

import android.content.Context
import android.content.pm.PackageManager
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.source.MediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.Collections

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

    private val players: MutableMap<Int, AudioPlayer> = Collections.synchronizedMap(mutableMapOf())
    private val recorders: MutableMap<Int, OpusAudioRecorder> = Collections.synchronizedMap(mutableMapOf())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ogg_record_player")
        channel.setMethodCallHandler(this)
        RemoteAudioCache.purgeExpiredFiles(context)
    }

    // Same checks as Darwin, so both platforms report a missing file the same way instead of an idle player.
    @OptIn(UnstableApi::class)
    private fun createFromFile(path: String, result: Result) {
        if (!File(path).isFile) {
            result.fail(PlayerError.FILE_NOT_FOUND, path)
            return
        }
        registerPlayer(result) { fileMediaSource(context, path) }
    }

    private fun createFromUrl(url: String, result: Result) {
        RemoteAudioCache.localFile(context, url) { download ->
            download.fold(
                onSuccess = { file -> createFromFile(file.path, result) },
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
            players[id] = AudioPlayer(context, mediaSource()) {
                handlePlayerStateChanged(id, it)
            }
            result.success(id)
        } catch (e: Exception) {
            result.fail(PlayerError.from(e), e.localizedMessage)
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
                if (url == null || !RemoteAudioCache.isRemote(url)) {
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

            "play" -> {
                (call.arguments as? Int)?.let {
                    players[it]?.play()
                }
                result.success(null)
            }

            "getDuration" -> {
                when (call.arguments) {
                    null -> {
                        result.success(null)
                    }

                    is Int -> {
                        android.util.Log.d("getDuration","getDuration native ${players[call.arguments as Int]?.duration}")
                        result.success(players[call.arguments as Int]?.duration)
                    }

                    else -> {
                        result.success(null)
                    }
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
                    players[it]?.destroy()
                    players.remove(it)
                }
                result.success(null)
            }

            "setPlaybackSpeed" -> {
                val playerId = call.argument<Int>("playerId")
                val speed = call.argument<Double>("speed")
                val player = players[playerId]
                if (player != null && speed != null) {
                    player.playbackRate = speed
                    handlePlayerStateChanged(playerId!!, player)
                }
                result.success(null)
            }

            "createRecorder" -> {
                val path = call.arguments as String
                val id = generatePlayerId()
                val recorder =
                    OpusAudioRecorder(context, File(path), object : OpusAudioRecorder.Callback {
                        override fun onCancel() {
                            channel.invokeMethod(
                                "onRecorderCanceled", mapOf(
                                    "recorderId" to id,
                                    "reason" to 0,
                                )
                            )
                        }

                        override fun sendAudio(file: File, duration: Long, waveForm: ByteArray) {
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
                    recorders[it]?.startRecording()
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
            )
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
