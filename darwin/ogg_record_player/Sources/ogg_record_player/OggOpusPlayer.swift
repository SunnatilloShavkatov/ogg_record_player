import AVFoundation
import Foundation

/// Session ownership and public state stay on main; decoding and buffer refill
/// belong to OggOpusPlayback's serial queue.
final class OggOpusPlayer {
  enum Status: Int {
    case initial = 0
    case playing = 1
    case paused = 2
    case stopped = 3
  }

  var onStatusChanged: ((OggOpusPlayer) -> Void)?
  private(set) var status: Status = .stopped {
    didSet { onStatusChanged?(self) }
  }

  let duration: Float64
  private let playback: OggOpusPlayback
  private var lastPosition: Float64 = 0
  private var wantsPlayback = false
  private var resumeAfterInterruption = false
  private var generation = 0

  var currentTime: Float64 {
    assert(Queue.main.isCurrent)
    if status != .stopped {
      lastPosition = min(duration, max(0, playback.position ?? lastPosition))
    }
    return lastPosition
  }

  var playRate: Float = 1 {
    didSet {
      assert(Queue.main.isCurrent)
      playRate = playRate.isFinite ? min(2, max(0.5, playRate)) : oldValue
      playback.setRate(playRate)
    }
  }

  convenience init(path: String) throws {
    try self.init(reader: OggOpusReader(fileAtPath: path))
  }

  convenience init(data: Data) throws {
    try self.init(reader: OggOpusReader(data: data))
  }

  private init(reader: OggOpusReader) throws {
    duration = reader.duration
    playback = try OggOpusPlayback(reader: reader)
    playback.onFinished = { [weak self] generation, reachedEnd in
      guard let self = self, self.generation == generation, self.wantsPlayback else { return }
      self.lastPosition = reachedEnd ? self.duration : (self.playback.position ?? self.lastPosition)
      self.wantsPlayback = false
      self.resumeAfterInterruption = false
      self.status = .stopped
      self.deactivateAudioSession()
    }
  }

  deinit {
    playback.dispose()
    deactivateAudioSession()
  }

  func play() {
    assert(Queue.main.isCurrent)
    guard !wantsPlayback, activateAudioSession() else { return }
    resumeAfterInterruption = false
    wantsPlayback = true
    generation += 1
    let command = generation
    let restart = status == .stopped
    if restart { lastPosition = 0 }
    playback.start(restart: restart, rate: playRate, generation: command) { [weak self] started in
      guard let self = self, self.generation == command, self.wantsPlayback else { return }
      if started {
        self.status = .playing
      } else {
        self.wantsPlayback = false
        self.status = .stopped
        self.deactivateAudioSession()
      }
    }
  }

  func pause() {
    assert(Queue.main.isCurrent)
    // Also cancel resumption when the UI pauses an already interrupted player.
    resumeAfterInterruption = false
    pausePlayback()
    deactivateAudioSession()
  }

  private func pausePlayback() {
    guard wantsPlayback || status == .playing else { return }
    wantsPlayback = false
    generation += 1
    lastPosition = playback.pause(generation: generation) ?? lastPosition
    status = .paused
  }

  func stop() {
    assert(Queue.main.isCurrent)
    resumeAfterInterruption = false
    wantsPlayback = false
    generation += 1
    lastPosition = currentTime
    playback.stop(generation: generation)
    status = .stopped
    deactivateAudioSession()
  }

  private func activateAudioSession() -> Bool {
    do {
      try AudioSession.shared.activate(client: self) { session in
        // No mixing/ducking: other media yields while this player runs.
        // The system selects the output, including Bluetooth A2DP.
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
      }
      return true
    } catch {
      return false
    }
  }

  private func deactivateAudioSession() {
    // A queued deactivation could otherwise silence a later play() on this instance.
    try? AudioSession.shared.deactivate(client: self, notifyOthersOnDeactivation: true)
  }
}

extension OggOpusPlayer: AudioSessionClient {
  var priority: AudioSessionClientPriority { .playback }

  func audioSessionDidBeganInterruption(_ audioSession: AudioSession, mayResume: Bool) {
    resumeAfterInterruption = mayResume && wantsPlayback
    pausePlayback()
    // The OS already deactivated the session; keep the interrupted client until
    // the matching end notification, unless the user explicitly pauses it.
  }

  func audioSessionDidEndInterruption(_ audioSession: AudioSession, shouldResume: Bool) {
    let resume = resumeAfterInterruption && shouldResume
    resumeAfterInterruption = false
    if resume { play() }
  }
}
