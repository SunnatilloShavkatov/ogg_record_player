import AVFoundation

/// Receives a recorder's events on the main thread.
protocol OggOpusRecorderDelegate: AnyObject {
  func oggOpusRecorderIsWaitingForActivation(_ recorder: OggOpusRecorder)
  func oggOpusRecorderDidStartRecording(_ recorder: OggOpusRecorder)
  func oggOpusRecorder(_ recorder: OggOpusRecorder, didCancelRecordingForReason reason: OggOpusRecorder.CancelledReason, userInfo: [String: Any]?)
  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFailRecordingWithError error: Error)
  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFinishRecordingWithMetadata data: AudioMetadata)
  func oggOpusRecorderDidDetectAudioSessionInterruptionEnd(_ recorder: OggOpusRecorder)
}
