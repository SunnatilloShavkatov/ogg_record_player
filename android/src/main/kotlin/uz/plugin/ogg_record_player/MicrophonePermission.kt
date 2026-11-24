package uz.plugin.ogg_record_player

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

/**
 * The `RECORD_AUDIO` permission of one engine: its status, the system prompt (which needs the engine's activity)
 * and the app's settings page. Statuses are the shared codes below, mirrored by Dart's `MicrophonePermission`.
 */
internal class MicrophonePermission(private val context: Context) : PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val GRANTED = 0
        const val DENIED = 1
        const val PERMANENTLY_DENIED = 2
        const val UNDETERMINED = 3

        private const val REQUEST_CODE = 0x4F52
        private const val PREFERENCES = "uz.plugin.ogg_record_player"

        /** Android cannot tell "never asked" from "don't ask again" without remembering that it asked. */
        private const val REQUESTED_KEY = "microphone_requested"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var binding: ActivityPluginBinding? = null

    /** Callers waiting for the prompt that is on screen; one prompt answers them all. */
    private val pending = mutableListOf<OggRecordPlayerApi.PermissionCallback>()

    val isGranted: Boolean
        get() = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun status(): Int {
        if (isGranted) return GRANTED
        if (!wasRequested()) return UNDETERMINED
        val activity = binding?.activity ?: return DENIED
        // After a refusal Android shows the prompt again only while it asks for a rationale.
        return if (activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)) {
            DENIED
        } else {
            PERMANENTLY_DENIED
        }
    }

    /** Shows the system prompt unless the answer is already known; without an activity answers the status. */
    fun request(callback: OggRecordPlayerApi.PermissionCallback) = onMain {
        val activity = binding?.activity
        if (isGranted || activity == null) {
            callback.onResult(status())
            return@onMain
        }
        pending += callback
        if (pending.size > 1) return@onMain
        markRequested()
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_CODE)
    }

    /** Opens this app's page in the system settings, where a permanently refused permission can be granted. */
    fun openAppSettings(): Boolean = runCatching {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        val activity: Activity? = binding?.activity
        if (activity != null) {
            activity.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }.isSuccess

    fun attach(activityBinding: ActivityPluginBinding) {
        binding = activityBinding
        activityBinding.addRequestPermissionsResultListener(this)
    }

    /** [configChange] keeps waiting callers: the recreated activity delivers the prompt's answer. */
    fun detach(configChange: Boolean) {
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        if (!configChange) answerPending()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        answerPending()
        return true
    }

    private fun answerPending() {
        if (pending.isEmpty()) return
        val result = status()
        val callbacks = pending.toList()
        pending.clear()
        callbacks.forEach { it.onResult(result) }
    }

    private fun preferences() = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun wasRequested() = preferences().getBoolean(REQUESTED_KEY, false)

    private fun markRequested() = preferences().edit().putBoolean(REQUESTED_KEY, true).apply()

    private fun onMain(work: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) work() else mainHandler.post(work)
    }
}
