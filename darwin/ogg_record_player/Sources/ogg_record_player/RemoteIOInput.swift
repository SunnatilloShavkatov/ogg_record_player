import AVFoundation
import Foundation

// See kAudioUnitSubType_RemoteIO
enum RemoteIOBus {
  static let output: UInt32 = 0
  static let input: UInt32 = 1
}

func audioRecorderNativeStreamDescription(_ sampleRate: Float64) -> AudioStreamBasicDescription {
  let bitsPerChannel: UInt32 = 16
  let channelsPerFrame: UInt32 = 1
  let bytesPerFrame: UInt32 = (bitsPerChannel / 8) * channelsPerFrame
  return .init(
    mSampleRate: Float64(sampleRate),
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
    mBytesPerPacket: bytesPerFrame,
    mFramesPerPacket: 1,
    mBytesPerFrame: bytesPerFrame,
    mChannelsPerFrame: channelsPerFrame,
    mBitsPerChannel: bitsPerChannel,
    mReserved: 0
  )
}

/// Builds the microphone-only RemoteIO unit the recorder reads from.
enum RemoteIOInput {
  /// Returns an initialized, not yet started unit that feeds microphone audio to `callback`.
  /// A unit that fails to configure is disposed before the error is thrown.
  static func makeAudioUnit(
    streamFormat: AudioStreamBasicDescription,
    callback: AURenderCallbackStruct
  ) throws -> AudioUnit {
    var acd = AudioComponentDescription(
      componentType: kAudioUnitType_Output,
      componentSubType: kAudioUnitSubType_RemoteIO,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0,
      componentFlagsMask: 0
    )
    guard let component = AudioComponentFindNext(nil, &acd) else {
      throw OggOpusRecorder.Error.missingAudioComponent
    }

    var newUnit: AudioUnit?
    let created = AudioComponentInstanceNew(component, &newUnit)
    guard created == noErr, let audioUnit = newUnit else {
      throw OggOpusRecorder.Error.newAudioUnit(created)
    }

    do {
      try configure(audioUnit, streamFormat: streamFormat, callback: callback)
    } catch {
      AudioComponentInstanceDispose(audioUnit)
      throw error
    }
    return audioUnit
  }

  private static func configure(
    _ audioUnit: AudioUnit,
    streamFormat: AudioStreamBasicDescription,
    callback: AURenderCallbackStruct
  ) throws {
    var status = setProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, RemoteIOBus.input, UInt32(1))
    guard status == noErr else {
      throw OggOpusRecorder.Error.enableInput(status)
    }

    status = setProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, RemoteIOBus.output, UInt32(0))
    guard status == noErr else {
      throw OggOpusRecorder.Error.disableOutput(status)
    }

    status = setProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, RemoteIOBus.input, streamFormat)
    guard status == noErr else {
      throw OggOpusRecorder.Error.setStreamFormat(status)
    }

    #if os(iOS)
      status = setProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, RemoteIOBus.output, streamFormat)
      guard status == noErr else {
        throw OggOpusRecorder.Error.setStreamFormat(status)
      }
    #endif

    status = setProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, RemoteIOBus.input, callback)
    guard status == noErr else {
      throw OggOpusRecorder.Error.setRecordingCallback(status)
    }

    status = AudioUnitInitialize(audioUnit)
    guard status == noErr else {
      throw OggOpusRecorder.Error.initializeAudioUnit(status)
    }
  }

  private static func setProperty<Value>(
    _ audioUnit: AudioUnit,
    _ property: AudioUnitPropertyID,
    _ scope: AudioUnitScope,
    _ bus: UInt32,
    _ value: Value
  ) -> OSStatus {
    var value = value
    return AudioUnitSetProperty(audioUnit, property, scope, bus, &value, UInt32(MemoryLayout<Value>.size))
  }
}
