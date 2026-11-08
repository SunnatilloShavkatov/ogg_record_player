package uz.plugin.ogg_record_player

/** The two worker threads of a recording: one reads the microphone, the other encodes to the file. */
internal class RecorderQueues {
    private val recordDelegate = lazy {
        DispatchQueue("recordQueue").apply { priority = Thread.MAX_PRIORITY }
    }
    private val fileEncodingDelegate = lazy {
        DispatchQueue("fileEncodingQueue").apply { priority = Thread.MAX_PRIORITY }
    }

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
