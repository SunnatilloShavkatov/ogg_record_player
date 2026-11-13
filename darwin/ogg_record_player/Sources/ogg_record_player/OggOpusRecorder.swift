import AVFoundation
import Foundation

fileprivate let millisecondsPerSecond: TimeInterval = 1000

final class OggOpusRecorder {
  enum Error: Swift.Error {
    case mediaServiceWereReset
    case missingAudioComponent
    case newAudioUnit(OSStatus)
    case disableOutput(OSStatus)
    case enableInput(OSStatus)
    case setRecordingCallback(OSStatus)
    case setStreamFormat(OSStatus)
    case initializeAudioUnit(OSStatus)
    case startAudioUnit(OSStatus)
  }

  enum CancelledReason: UInt {
    case audioSessionInterrupted = 0
    case audioRouteChange = 1
    case bufferEnqueueFailed = 2
    case userInitiated = 3
    /// The encoder failed to write, or the recording was too short to form a valid stream; the file is deleted.
    case unusableRecording = 4
  }

  let path: String

  var delegate: OggOpusRecorderDelegate?

  @Synchronized(value: false)
  private(set) var isRecording: Bool

  private var writer: OggOpusWriter?
  private let processingQueue = DispatchQueue(label: "uz.plugin.messenger.OggOpusRecorder")

  fileprivate var audioUnit: AudioUnit?

  private var retainedSelf: Unmanaged<OggOpusRecorder>?
  private var waveform = WaveformBuilder()
  private var numberOfEncodedSamples: UInt = 0
  private var duration: TimeInterval = 0
  private var stopAfterNumberOfPackets: Int?

  private weak var timer: Timer?
  private var sampleRate: Int32 = 0

  public init(path: String) {
    self.path = path
  }

  func record(for duration: TimeInterval) {
    #if os(iOS)
      if AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint {
        DispatchQueue.main.async {
          self.delegate?.oggOpusRecorderIsWaitingForActivation(self)
        }
      }
    #endif
    processingQueue.async { [weak self] in
      // A second start while recording would open another audio unit on the same file.
      guard let self = self, !self.isRecording else {
        return
      }

      #if os(iOS)
        do {
          try AudioSession.shared.activate(client: self) { session in
            // `allowBluetooth` was renamed to `allowBluetoothHFP` in the iOS 26 SDK
            // (Swift 6.2 toolchain). Keep the old spelling for older toolchains.
            #if compiler(>=6.2)
              let options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]
            #else
              let options: AVAudioSession.CategoryOptions = [.allowBluetooth]
            #endif
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: options)
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            // Voice messages need no low latency; 20 ms buffers mean 4x fewer render callbacks, each of which
            // allocates and hands a buffer to `processingQueue`, than the 5 ms used before.
            try session.setPreferredIOBufferDuration(0.02)
          }
        } catch {
          DispatchQueue.main.async {
            self.delegate?.oggOpusRecorder(self, didFailRecordingWithError: error)
          }
          return
        }
      #endif
      do {
        self.duration = duration
        self.stopAfterNumberOfPackets = nil
        // The same recorder can record again; nothing of the previous recording may leak into this one.
        self.numberOfEncodedSamples = 0
        self.waveform = WaveformBuilder()
        try self.startRecording()
        DispatchQueue.main.async {
          self.delegate?.oggOpusRecorderDidStartRecording(self)
        }
      } catch {
        self.discardFailedStart()
        #if os(iOS)
          try? AudioSession.shared.deactivate(client: self, notifyOthersOnDeactivation: true)
        #endif
        DispatchQueue.main.async {
          self.delegate?.oggOpusRecorder(self, didFailRecordingWithError: error)
        }
      }
    }
  }

  func stop() {
    processingQueue.async {
      let numberOfPackets = 0.1 / AVAudioSession.sharedInstance().ioBufferDuration
      self.stopAfterNumberOfPackets = Int(ceil(numberOfPackets))
    }
  }

  /// `completion` runs on main once nothing is recording any more and the audio session is released.
  func cancel(for reason: CancelledReason, userInfo: [String: Any]? = nil, completion: (() -> Void)? = nil) {
    processingQueue.async {
      guard self.isRecording else {
        if let completion = completion {
          DispatchQueue.main.async(execute: completion)
        }
        return
      }
      self.close()
      #if os(iOS)
        try? AudioSession.shared.deactivate(client: self, notifyOthersOnDeactivation: true)
      #endif
      try? FileManager.default.removeItem(atPath: self.path)
      DispatchQueue.main.async {
        self.delegate?.oggOpusRecorder(self, didCancelRecordingForReason: reason, userInfo: userInfo)
        completion?()
      }
    }
  }

  /// The media services daemon restarted: the audio unit is gone, so the recording cannot continue.
  func mediaServicesWereReset() {
    isRecording = false
    DispatchQueue.main.async {
      self.delegate?.oggOpusRecorder(self, didFailRecordingWithError: Error.mediaServiceWereReset)
    }
  }
}

extension OggOpusRecorder {
  private func startRecording() throws {
    sampleRate = 16000
    writer = try OggOpusWriter(path: path, inputSampleRate: sampleRate)

    let retainedSelf = Unmanaged.passRetained(self)
    let callback = AURenderCallbackStruct(
      inputProc: recordingCallback(_:_:_:_:_:_:),
      inputProcRefCon: retainedSelf.toOpaque()
    )
    let unit: AudioUnit
    do {
      unit = try RemoteIOInput.makeAudioUnit(
        streamFormat: audioRecorderNativeStreamDescription(Float64(sampleRate)),
        callback: callback
      )
    } catch {
      retainedSelf.release()
      throw error
    }
    audioUnit = unit

    let result = AudioOutputUnitStart(unit)
    guard result == noErr else {
      AudioComponentInstanceDispose(unit)
      retainedSelf.release()
      throw Error.startAudioUnit(result)
    }

    let timer = Timer(timeInterval: duration, repeats: false) { _ in
      self.stopRecording()
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer

    self.isRecording = true
    self.retainedSelf = retainedSelf
  }

  /// Releases what a failed `startRecording()` left behind: the encoder with its half-written file, and the
  /// reference to the audio unit that every failing path has already disposed.
  private func discardFailedStart() {
    writer?.close()
    writer = nil
    audioUnit = nil
    try? FileManager.default.removeItem(atPath: path)
  }

  private func stopRecording() {
    processingQueue.async {
      guard self.isRecording else {
        return
      }
      let finalized = self.close()
      guard finalized else {
        try? FileManager.default.removeItem(atPath: self.path)
        DispatchQueue.main.async {
          self.delegate?.oggOpusRecorder(self, didCancelRecordingForReason: .unusableRecording, userInfo: nil)
        }
        #if os(iOS)
          try? AudioSession.shared.deactivate(client: self, notifyOthersOnDeactivation: true)
        #endif
        return
      }
      let waveform = self.waveform.makeWaveform()
      let duration = self.numberOfEncodedSamples * UInt(millisecondsPerSecond) / UInt(self.sampleRate)
      let metadata = AudioMetadata(duration: duration, waveform: waveform)
      DispatchQueue.main.async {
        self.delegate?.oggOpusRecorder(self, didFinishRecordingWithMetadata: metadata)
      }
      #if os(iOS)
        try? AudioSession.shared.deactivate(client: self, notifyOthersOnDeactivation: true)
      #endif
    }
  }

  /// Stops the audio unit and closes the writer. Returns whether the file is a complete, playable stream.
  @discardableResult
  private func close() -> Bool {
    self.timer?.invalidate()
    self.retainedSelf?.release()
    self.retainedSelf = nil
    if let audioUnit = self.audioUnit {
      AudioOutputUnitStop(audioUnit)
      AudioComponentInstanceDispose(audioUnit)
    }
    let finalized = self.writer?.close() ?? false
    self.isRecording = false
    return finalized
  }

  fileprivate func process(size: Int, render: (inout AudioBufferList) -> OSStatus) -> OSStatus {
    let pcmBytes = malloc(size)!
    let buffer = AudioBuffer(mNumberChannels: 1,
                             mDataByteSize: UInt32(size),
                             mData: pcmBytes)
    var bufferList = AudioBufferList(mNumberBuffers: 1,
                                     mBuffers: buffer)
    let result = render(&bufferList)
    // Owns the buffer before any early return below, so a callback queued after the recorder stopped frees it.
    let pcmData = Data(bytesNoCopy: pcmBytes,
                       count: size,
                       deallocator: .free)
    processingQueue.async { [weak self] in
      guard let self = self, self.isRecording else {
        return
      }
      if let number = self.stopAfterNumberOfPackets {
        if number > 0 {
          self.stopAfterNumberOfPackets = number - 1
        } else {
          self.stopRecording()
        }
      }
      self.numberOfEncodedSamples += UInt(pcmData.count / 2)
      self.writer?.write(pcmData: pcmData)
      if self.writer?.writeFailed == true {
        self.cancel(for: .unusableRecording)
      }
      self.waveform.append(pcmData: pcmData)
    }
    return result
  }
}

fileprivate func recordingCallback(
  _ inRefCon: UnsafeMutableRawPointer,
  _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
  _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
  _ inBusNumber: UInt32,
  _ inNumberFrames: UInt32,
  _ ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
  let recorder = Unmanaged<OggOpusRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
  guard let audioUnit = recorder.audioUnit else {
    return noErr
  }
  return recorder.process(size: Int(inNumberFrames) * 2) { bufferList -> OSStatus in
    AudioUnitRender(audioUnit,
                    ioActionFlags,
                    inTimeStamp,
                    RemoteIOBus.input,
                    inNumberFrames,
                    &bufferList)
  }
}
