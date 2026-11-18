package uz.plugin.ogg_record_player

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Only the engine lifecycle: Dart calls [OggRecordPlayerApi] through JNI, so there is no channel. Each attached
 * engine gets its own [OggRecordPlayerHost], keyed by its engine id; detaching releases only that engine's players
 * and recorders.
 */
class OggRecordPlayerPlugin : FlutterPlugin {

    private var host: OggRecordPlayerHost? = null
    private var engineId: Long = OggRecordPlayerHost.NO_ENGINE

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        // The id Dart reads from `PlatformDispatcher.instance.engineId`. The binding exposes it only through the
        // engine on every supported Flutter version.
        @Suppress("DEPRECATION")
        val id = flutterPluginBinding.flutterEngine.engineId
        val attached = OggRecordPlayerHost(flutterPluginBinding.applicationContext)
        host = attached
        engineId = id
        OggRecordPlayerHost.attach(id, attached)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val detached = host ?: return
        host = null
        OggRecordPlayerHost.detach(engineId, detached)
    }
}
