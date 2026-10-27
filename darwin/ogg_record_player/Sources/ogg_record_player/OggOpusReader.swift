import Foundation
#if canImport(ogg_record_player_c)
import ogg_record_player_c
#endif

class OggOpusReader {
    
    enum Error: Swift.Error {
        case memoryAllocation
        case openFile(Int32)
        case read(Int32)
    }
    
    private(set) var didReachEnd = false

    /// Duration of the whole stream, in seconds, or `nil` when opusfile cannot tell (e.g. an unseekable stream).
    /// Opus always decodes at 48 kHz.
    var duration: Float64? {
        let samples = op_pcm_total(file, -1)
        guard samples > 0 else {
            return nil
        }
        return Float64(samples) / 48000
    }

    private let file: OpaquePointer

    /// The encoded stream for `init(data:)`; opusfile reads it in place, so it lives as long as `file`.
    private let memory: UnsafeMutableRawPointer?
    
    init(fileAtPath path: String) throws {
        var result: Int32 = 0
        let file = path.withCString { (cPath) -> OpaquePointer? in
            op_open_file(cPath, &result)
        }
        if result == 0, let file = file {
            self.file = file
            memory = nil
        } else {
            throw Error.openFile(result)
        }
    }

    /// Decodes `data` from memory, without writing it to a file. The bytes are copied once, since `Data` does not
    /// guarantee a stable address outside `withUnsafeBytes`.
    init(data: Data) throws {
        guard let memory = malloc(max(data.count, 1)) else {
            throw Error.memoryAllocation
        }
        data.copyBytes(to: memory.assumingMemoryBound(to: UInt8.self), count: data.count)
        var result: Int32 = 0
        let file = op_open_memory(memory.assumingMemoryBound(to: UInt8.self), data.count, &result)
        if result == 0, let file = file {
            self.file = file
            self.memory = memory
        } else {
            free(memory)
            throw Error.openFile(result)
        }
    }
    
    deinit {
        op_free(file)
        free(memory)
    }
    
    func rewind() throws {
        let result = op_pcm_seek(file, 0)
        guard result == 0 else {
            throw Error.read(result)
        }
        didReachEnd = false
    }

    /// Writes 48 kHz interleaved stereo straight into an AudioQueue buffer.
    /// A fixed channel count also supports chained streams whose channel count changes.
    func readPCM(into buffer: UnsafeMutableRawPointer, byteCapacity: Int32) throws -> Int {
        let output = buffer.assumingMemoryBound(to: opus_int16.self)
        let capacity = byteCapacity / 2
        var written: Int32 = 0
        var holes = 0
        while capacity - written >= 2 && !didReachEnd {
            let frames = op_read_stereo(file, output.advanced(by: Int(written)), capacity - written)
            if frames == OP_HOLE {
                // A discontinuity consumes no output space. Never subtract its negative
                // error code from the remaining capacity (which could overflow the buffer).
                holes += 1
                guard holes <= 16 else { throw Error.read(frames) }
                continue
            }
            guard frames >= 0 else { throw Error.read(frames) }
            if frames == 0 {
                didReachEnd = true
            } else {
                written += frames * 2
                holes = 0
            }
        }
        return Int(written) * MemoryLayout<opus_int16>.size
    }
}
