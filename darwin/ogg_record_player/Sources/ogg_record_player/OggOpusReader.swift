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

    /// Duration of the whole stream, in seconds. Opus always decodes at 48 kHz.
    var duration: Float64 {
        let samples = op_pcm_total(file, -1)
        guard samples > 0 else {
            return 0
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
    
    func pcmData(maxLength: Int32) throws -> Data {
        guard let buffer = malloc(Int(maxLength)) else {
            throw Error.memoryAllocation
        }
        defer {
            free(buffer)
        }
        
        let output = buffer.assumingMemoryBound(to: opus_int16.self)
        let outputLength = maxLength / 2
        var remainingOutputLength = outputLength
        
        var result: Int32 = 1
        while (result == OP_HOLE || result > 0) && remainingOutputLength > 0 {
            let position = output.advanced(by: Int(outputLength - remainingOutputLength))
            result = op_read(file, position, remainingOutputLength, nil)
            remainingOutputLength -= result
        }
        
        if result < 0 {
            throw Error.read(result)
        } else {
            let count = Int(outputLength - remainingOutputLength) * 2
            if count == 0 {
                didReachEnd = true
                return Data()
            } else {
                return Data(bytes: buffer, count: count)
            }
        }
    }
}
