#if os(iOS)
import Foundation
import AVFoundation

/// All ownership changes and client callbacks run on main. No callback is made
/// while holding a lock, so a client can pause/deactivate during a takeover.
class AudioSession {
    enum Error: Swift.Error {
        case insufficientPriority(AudioSessionClientPriority)
        case interrupted
    }

    static let shared = AudioSession()
    let avAudioSession = AVAudioSession.sharedInstance()
    private weak var currentClient: AudioSessionClient?
    private weak var interruptedClient: AudioSessionClient?
    private var isInterrupted = false

    init() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(audioSessionInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(audioSessionRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(audioSessionMediaServicesWereReset(_:)),
                           name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    func activate(client: AudioSessionClient, config: ((AVAudioSession) throws -> Void)? = nil) throws {
        try Queue.main.autoSync {
            guard !isInterrupted else { throw Error.interrupted }
            if let previous = currentClient, previous !== client {
                guard previous.priority <= client.priority else {
                    throw Error.insufficientPriority(previous.priority)
                }
                currentClient = nil
                previous.audioSessionDidBeganInterruption(self, mayResume: false)
            }
            do {
                try config?(avAudioSession)
                try avAudioSession.setActive(true, options: [])
                currentClient = client
            } catch {
                // A failed takeover must not leave an active session with no
                // owner after the previous player/recorder has been paused.
                currentClient = nil
                try? avAudioSession.setActive(false, options: .notifyOthersOnDeactivation)
                throw error
            }
        }
    }

    func deactivate(client: AudioSessionClient, notifyOthersOnDeactivation: Bool) throws {
        try Queue.main.autoSync {
            // A manual pause/disposal during a call cancels automatic resumption.
            if interruptedClient === client {
                interruptedClient = nil
            }
            guard currentClient === client else { return }
            let options: AVAudioSession.SetActiveOptions = notifyOthersOnDeactivation
                ? .notifyOthersOnDeactivation : []
            try avAudioSession.setActive(false, options: options)
            currentClient = nil
        }
    }

    @objc private func audioSessionInterruption(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber,
              let type = AVAudioSession.InterruptionType(rawValue: value.uintValue) else { return }
        let optionsValue = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
        Queue.main.autoAsync {
            switch type {
            case .began:
                guard !self.isInterrupted else { return }
                self.isInterrupted = true
                self.interruptedClient = self.currentClient
                self.currentClient = nil
                self.interruptedClient?.audioSessionDidBeganInterruption(self, mayResume: true)
            case .ended:
                self.isInterrupted = false
                let client = self.interruptedClient
                self.interruptedClient = nil
                client?.audioSessionDidEndInterruption(self, shouldResume: shouldResume)
            @unknown default:
                break
            }
        }
    }

    @objc private func audioSessionRouteChange(_ notification: Notification) {
        guard let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
              let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber,
              let reason = AVAudioSession.RouteChangeReason(rawValue: value.uintValue) else { return }
        Queue.main.autoAsync {
            (self.currentClient ?? self.interruptedClient)?.audioSession(self, didChangeRouteFrom: previous, reason: reason)
        }
    }

    @objc private func audioSessionMediaServicesWereReset(_ notification: Notification) {
        Queue.main.autoAsync {
            let client = self.currentClient ?? self.interruptedClient
            self.currentClient = nil
            self.interruptedClient = nil
            self.isInterrupted = false
            client?.audioSessionMediaServicesWereReset(self)
        }
    }
}
#endif
