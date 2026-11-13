package uz.plugin.ogg_record_player

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Only the engine lifecycle: Dart calls [OggRecordPlayerApi] through JNI, so there is no channel. Each attached
 * engine gets its own [OggRecordPlayerHost]; detaching releases its players and recorders.
 */
class OggRecordPlayerPlugin : FlutterPlugin {

    private var host: OggRecordPlayerHost? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val attached = OggRecordPlayerHost(flutterPluginBinding.applicationContext)
        host = attached
        OggRecordPlayerHost.current = attached
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val detached = host ?: return
        host = null
        if (OggRecordPlayerHost.current === detached) OggRecordPlayerHost.current = null
        detached.detach()
    }
}
