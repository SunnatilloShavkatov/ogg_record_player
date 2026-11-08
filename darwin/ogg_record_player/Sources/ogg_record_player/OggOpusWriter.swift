import Foundation
#if canImport(ogg_record_player_c)
import ogg_record_player_c
#endif

fileprivate let numberOfChannels: Int32 = 1;
fileprivate let outputBitRate: Int32 = 16 * 1024;

/// `ope_encoder_drain` on a very short or failed stream does not close cleanly. Drain only recordings that are
/// long enough and error-free; anything else is destroyed without draining and reported as unusable. Matches
/// `MIN_DRAIN_SAMPLES` in Android's `audio.c`.
fileprivate let minDrainSamples: Int64 = 4000

class OggOpusWriter {
    
    enum Error: Swift.Error {
        case createComments
        case createEncoder(Int32)
        case setBitrate(Int32)
    }
    
    private let comments: OpaquePointer
    private let encoder: OpaquePointer
    private var samplesWritten: Int64 = 0
    private(set) var writeFailed = false
    private var isClosed = false
    
    init(path: String, inputSampleRate: Int32) throws {
        guard let comments = ope_comments_create() else {
            throw Error.createComments
        }
        
        var result = OPE_OK
        self.encoder = path.withCString { (cPath) -> OpaquePointer in
            ope_encoder_create_file(cPath,
                                    comments,
                                    inputSampleRate,
                                    numberOfChannels,
                                    0,
                                    &result)
        }
        guard result == OPE_OK else {
            ope_comments_destroy(comments)
            throw Error.createEncoder(result)
        }
        
        result = ope_encoder_set_bitrate(encoder, outputBitRate)
        guard result == OPE_OK else {
            ope_encoder_destroy(encoder)
            ope_comments_destroy(comments)
            throw Error.setBitrate(result)
        }
        
        self.comments = comments
    }
    
    func write(pcmData: Data) {
        let numberOfPCMSamples = pcmData.count / 2
        assert(numberOfPCMSamples < Int32.max)
        pcmData.withUnsafeBytes { (buffer) -> Void in
            let pcm = buffer.bindMemory(to: opus_int16.self).baseAddress
            let result = ope_encoder_write(encoder, pcm, Int32(numberOfPCMSamples))
            if result == OPE_OK {
                samplesWritten += Int64(numberOfPCMSamples)
            } else {
                writeFailed = true
            }
        }
    }
    
    /// Closes the encoder and returns whether the file is a complete stream. A recording that was too short or had
    /// write errors is not drained, so its file is unusable and the caller must discard it. Safe to call more
    /// than once; later calls return the same answer without touching the encoder.
    @discardableResult
    func close() -> Bool {
        let finalized = !writeFailed && samplesWritten >= minDrainSamples
        guard !isClosed else {
            return finalized
        }
        isClosed = true
        if finalized {
            ope_encoder_drain(encoder)
        }
        ope_encoder_destroy(encoder)
        ope_comments_destroy(comments)
        return finalized
    }
    
}
