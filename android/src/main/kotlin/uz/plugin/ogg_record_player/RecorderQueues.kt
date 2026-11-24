package uz.plugin.ogg_record_player

import android.os.Process

/** The two worker threads of a recording: one reads the microphone, the other encodes to the file. */
internal class RecorderQueues {
    // Only the microphone reader is audio-critical; encoding keeps the default priority so it never competes with
    // the UI thread.
    private val recordDelegate = lazy {
        DispatchQueue("recordQueue").apply {
            postRunnable { Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO) }
        }
    }
    private val fileEncodingDelegate = lazy { DispatchQueue("fileEncodingQueue") }

    val record: DispatchQueue by recordDelegate
    val fileEncoding: DispatchQueue by fileEncodingDelegate

    /**
     * Stops both worker threads. Only quits queues that were actually started so a
     * failed start does not spin up the encoding thread just to tear it down.
     */
    fun shutdown() {
        if (fileEncodingDelegate.isInitialized()) {
            fileEncoding.quit()
        }
        if (recordDelegate.isInitialized()) {
            record.quit()
        }
    }
}
