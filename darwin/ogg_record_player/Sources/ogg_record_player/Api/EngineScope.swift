import Foundation

/// One attached engine's players, recorders and the listeners its Dart side registered. Main thread only. Once
/// detached it emits nothing more, so a detached engine's events never reach another one.
final class EngineScope {
  var players: [Int: OggOpusPlayer] = [:]
  var recorders: [Int: OggOpusRecorder] = [:]

  var playerListener: ((Int, Int, Double, Double, Double, String?) -> Void)?
  var recorderCanceled: ((Int, Int) -> Void)?
  var recorderStartFailed: ((Int, String) -> Void)?
  var recorderFinished: ((Int, Int, Data) -> Void)?

  private(set) var isAttached = true

  func owns(_ id: Int) -> Bool {
    players[id] != nil || recorders[id] != nil
  }

  func emitState(id: Int, _ player: OggOpusPlayer) {
    guard isAttached else { return }
    playerListener?(id, player.status.rawValue, player.currentTime, player.duration ?? 0, Double(player.playRate), nil)
  }

  /// Releases every player and recorder and silences later events.
  func detach() {
    isAttached = false
    playerListener = nil
    recorderCanceled = nil
    recorderStartFailed = nil
    recorderFinished = nil
    players.values.forEach { $0.stop() }
    players.removeAll()
    recorders.values.forEach { $0.cancel(for: .userInitiated) }
    recorders.removeAll()
  }
}

/// Forwards one recorder's events to the listeners its engine's Dart side registered.
final class RecorderEventForwarder: OggOpusRecorderDelegate {
  let recorderId: Int
  private weak var scope: EngineScope?

  init(recorderId: Int, scope: EngineScope) {
    self.recorderId = recorderId
    self.scope = scope
  }

  func oggOpusRecorderIsWaitingForActivation(_ recorder: OggOpusRecorder) {}

  func oggOpusRecorderDidStartRecording(_ recorder: OggOpusRecorder) {}

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didCancelRecordingForReason reason: OggOpusRecorder.CancelledReason, userInfo: [String: Any]?) {
    scope?.recorderCanceled?(recorderId, Int(reason.rawValue))
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFailRecordingWithError error: Error) {
    scope?.recorderStartFailed?(recorderId, error.localizedDescription)
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFinishRecordingWithMetadata data: AudioMetadata) {
    scope?.recorderFinished?(recorderId, Int(data.duration), Data(data.waveform))
  }

  func oggOpusRecorderDidDetectAudioSessionInterruptionEnd(_ recorder: OggOpusRecorder) {}
}

extension EngineScope {
  /// For registrars that do not expose their engine identifier: negative, so never a real identifier. Main only.
  private static var lastSyntheticKey: Int64 = 0

  /// The key `registrar`'s engine is kept under: its identifier when the registrar exposes one (Flutter 3.50+),
  /// else a synthetic key that only the single-engine fallback in `OggRecordPlayerApi` can reach.
  static func key(of registrar: AnyObject) -> Int64 {
    let selector = NSSelectorFromString("engineIdentifier")
    if let object = registrar as? NSObject, object.responds(to: selector),
       let identifier = object.value(forKey: "engineIdentifier") as? NSNumber,
       identifier.int64Value != OggRecordPlayerApi.noEngine {
      return identifier.int64Value
    }
    let next = {
      lastSyntheticKey -= 1
      return lastSyntheticKey
    }
    return Thread.isMainThread ? next() : DispatchQueue.main.sync(execute: next)
  }
}
