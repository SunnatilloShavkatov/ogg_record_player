import AVFoundation
import Foundation

#if os(iOS)

  extension OggOpusRecorder: AudioSessionClient {
    var priority: AudioSessionClientPriority {
      .audioRecord
    }

    func audioSessionDidBeganInterruption(_ audioSession: AudioSession, mayResume: Bool) {
      cancel(for: .audioSessionInterrupted)
    }

    func audioSessionDidEndInterruption(_ audioSession: AudioSession, shouldResume: Bool) {
      delegate?.oggOpusRecorderDidDetectAudioSessionInterruptionEnd(self)
    }

    func audioSession(_ audioSession: AudioSession, didChangeRouteFrom previousRoute: AVAudioSessionRouteDescription, reason: AVAudioSession.RouteChangeReason) {
      let category = audioSession.avAudioSession.category
      let isCategoryAvailable = category == .record || category == .playAndRecord
      let hasInput = !audioSession.avAudioSession.currentRoute.inputs.isEmpty
      if !hasInput || !isCategoryAvailable {
        cancel(for: .audioRouteChange)
      }
    }

    func audioSessionMediaServicesWereReset(_ audioSession: AudioSession) {
      mediaServicesWereReset()
    }
  }

#endif
