package uz.plugin.ogg_record_player

/**
 * Keeps [SIZE] samples that stay evenly spread over everything recorded so far: each new buffer is squeezed in
 * proportionally and the older samples are thinned out. The native `getWaveform2` turns them into the waveform.
 * Not thread-safe; use it from the recording queue only.
 */
internal class WaveformSampler {
    companion object {
        const val SIZE = 1024
    }

    private val samples = ShortArray(SIZE)
    private var samplesCount = 0L

    fun reset() {
        samplesCount = 0
    }

    fun add(buffer: ShortArray, len: Int) {
        try {
            val newSamplesCount = samplesCount + len
            val currPart = (samplesCount / newSamplesCount.toDouble() * samples.size).toInt()
            val newPart = samples.size - currPart
            var sampleStep: Float
            if (currPart != 0) {
                sampleStep = samples.size / currPart.toFloat()
                var currNum = 0f
                for (i in 0 until currPart) {
                    samples[i] = samples[currNum.toInt()]
                    currNum += sampleStep
                }
            }
            var currNum = currPart
            var nextNum = 0f
            sampleStep = if (newPart > 0) len.toFloat() / newPart else 0f
            for (i in 0 until len) {
                if (i == nextNum.toInt() && currNum < samples.size) {
                    samples[currNum] = buffer[i]
                    nextNum += sampleStep
                    currNum++
                }
            }
            samplesCount = newSamplesCount
        } catch (_: Exception) {
        }
    }

    fun snapshot(): ShortArray = samples.copyOf()
}
