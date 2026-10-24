import AVFoundation
import Foundation

/// Owns AudioQueue and the decoder, but never retains the public player.
/// All mutable buffer state is confined to processingQueue.
final class OggOpusPlayback {
  enum Error: Swift.Error {
    case audioQueue(OSStatus)
  }

  var onFinished: ((Int, Bool) -> Void)?

  private let reader: OggOpusReader
  private let processingQueue = DispatchQueue(label: "uz.plugin.ogg_record_player.decode", qos: .userInitiated)
  private var audioQueue: AudioQueueRef?
  private var buffers = [AudioQueueBufferRef]()
  // Three 120 ms buffers at 48 kHz, stereo, signed 16-bit PCM.
  private let bufferByteCount: UInt32 = 48000 * 2 * 2 * 120 / 1000
  private var acceptsBuffers = false
  private var primed = false
  private var queuedBufferCount = 0
  private var paused = true
  private var draining = false
  private var decodeFailed = false
  private var completionSent = false
  private var generation = 0

  private var context: UnsafeMutableRawPointer {
    Unmanaged.passUnretained(self).toOpaque()
  }

  init(reader: OggOpusReader) throws {
    self.reader = reader
    var format = AudioStreamBasicDescription(
      mSampleRate: 48000,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
      mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
    )
    let result = AudioQueueNewOutputWithDispatchQueue(&audioQueue, &format, 0, processingQueue) { [weak self] queue, buffer in
      self?.refill(queue: queue, buffer: buffer)
    }
    guard result == noErr, let queue = audioQueue else { throw Error.audioQueue(result) }
    do {
      try check(AudioQueueAddPropertyListener(queue, kAudioQueueProperty_IsRunning, playbackRunningChanged, context))
      for _ in 0..<3 {
        var buffer: AudioQueueBufferRef?
        try check(AudioQueueAllocateBuffer(queue, bufferByteCount, &buffer))
        guard let buffer = buffer else { throw Error.audioQueue(kAudio_ParamError) }
        buffers.append(buffer)
      }
      var enabled: UInt32 = 1
      try check(AudioQueueSetProperty(queue, kAudioQueueProperty_EnableTimePitch, &enabled,
                                     UInt32(MemoryLayout.size(ofValue: enabled))))
    } catch {
      dispose()
      throw error
    }
  }

  var position: Float64? {
    processingQueue.sync {
      guard let queue = audioQueue else { return nil }
      var timestamp = AudioTimeStamp()
      guard AudioQueueGetCurrentTime(queue, nil, &timestamp, nil) == noErr else { return nil }
      return timestamp.mSampleTime / 48000
    }
  }

  func setRate(_ rate: Float) {
    processingQueue.async {
      if let queue = self.audioQueue {
        AudioQueueSetParameter(queue, kAudioQueueParam_PlayRate, rate)
      }
    }
  }

  func start(restart: Bool, rate: Float, generation: Int, completion: @escaping (Bool) -> Void) {
    processingQueue.async {
      guard let queue = self.audioQueue else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      self.generation = generation
      self.completionSent = false
      self.paused = false
      self.acceptsBuffers = true
      do {
        if restart {
          try self.check(AudioQueueReset(queue))
          try self.reader.rewind()
          self.primed = false
          self.queuedBufferCount = 0
          self.draining = false
          self.decodeFailed = false
        }
        if !self.primed {
          for buffer in self.buffers {
            if try self.enqueue(queue: queue, buffer: buffer) == false { break }
          }
          self.primed = true
        }
        if self.queuedBufferCount == 0 && self.reader.didReachEnd {
          DispatchQueue.main.async { completion(true) }
          self.finish()
          return
        }
        try self.check(AudioQueueSetParameter(queue, kAudioQueueParam_PlayRate, rate))
        try self.check(AudioQueueStart(queue, nil))
        DispatchQueue.main.async { completion(true) }
      } catch {
        self.acceptsBuffers = false
        AudioQueueStop(queue, true)
        DispatchQueue.main.async { completion(false) }
      }
    }
  }

  func pause(generation: Int) -> Float64? {
    processingQueue.sync {
      self.generation = generation
      paused = true
      if let queue = audioQueue { AudioQueuePause(queue) }
    }
    return position
  }

  func stop(generation: Int) {
    processingQueue.sync {
      self.generation = generation
      acceptsBuffers = false
      paused = true
      draining = false
      primed = false
      queuedBufferCount = 0
      if let queue = audioQueue { AudioQueueStop(queue, true) }
    }
  }

  /// Dispose from the control thread, outside any AudioQueue callback. Once it
  /// returns AudioQueue no longer invokes callbacks, including its raw context.
  func dispose() {
    stop(generation: 0)
    guard let queue = audioQueue else { return }
    AudioQueueRemovePropertyListener(queue, kAudioQueueProperty_IsRunning, playbackRunningChanged, context)
    AudioQueueDispose(queue, true)
    processingQueue.sync {
      audioQueue = nil
      buffers.removeAll()
    }
  }

  private func check(_ result: OSStatus) throws {
    guard result == noErr else { throw Error.audioQueue(result) }
  }

  private func enqueue(queue: AudioQueueRef, buffer: AudioQueueBufferRef) throws -> Bool {
    let count = try reader.readPCM(into: buffer.pointee.mAudioData, byteCapacity: Int32(bufferByteCount))
    guard count > 0 else { return false }
    buffer.pointee.mAudioDataByteSize = UInt32(count)
    try check(AudioQueueEnqueueBuffer(queue, buffer, 0, nil))
    queuedBufferCount += 1
    return true
  }

  private func refill(queue: AudioQueueRef, buffer: AudioQueueBufferRef) {
    guard acceptsBuffers, !draining else { return }
    queuedBufferCount -= 1
    if !decodeFailed {
      do {
        if try enqueue(queue: queue, buffer: buffer) { return }
      } catch {
        decodeFailed = true
      }
    }
    // Stop only once the last buffer has played. This also allows a short clip
    // (or the tail of a long one) to be paused and resumed before it completes.
    if queuedBufferCount == 0 {
      draining = true
      AudioQueueStop(queue, false)
    }
  }

  fileprivate func runningChanged() {
    processingQueue.async { [weak self] in
      guard let self = self, let queue = self.audioQueue,
            self.acceptsBuffers, self.draining, !self.paused, !self.completionSent else { return }
      var running: UInt32 = 0
      var size = UInt32(MemoryLayout.size(ofValue: running))
      guard AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size) == noErr,
            running == 0 else { return }
      self.finish()
    }
  }

  private func finish() {
    guard !completionSent else { return }
    completionSent = true
    acceptsBuffers = false
    let command = generation
    let reachedEnd = !decodeFailed && reader.didReachEnd
    let callback = onFinished
    DispatchQueue.main.async { callback?(command, reachedEnd) }
  }
}

private func playbackRunningChanged(_ context: UnsafeMutableRawPointer?, _ queue: AudioQueueRef, _ property: AudioQueuePropertyID) {
  guard let context = context else { return }
  Unmanaged<OggOpusPlayback>.fromOpaque(context).takeUnretainedValue().runningChanged()
}
