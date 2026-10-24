#if os(iOS)
import Foundation
import AVFoundation

protocol AudioSessionClient: AnyObject {
    var priority: AudioSessionClientPriority { get }
    func audioSessionDidBeganInterruption(_ audioSession: AudioSession, mayResume: Bool)
    func audioSessionDidEndInterruption(_ audioSession: AudioSession, shouldResume: Bool)
    func audioSession(_ audioSession: AudioSession, didChangeRouteFrom previousRoute: AVAudioSessionRouteDescription, reason: AVAudioSession.RouteChangeReason)
    func audioSessionMediaServicesWereReset(_ audioSession: AudioSession)
}

extension AudioSessionClient {
    
    func audioSessionDidBeganInterruption(_ audioSession: AudioSession, mayResume: Bool) {
        
    }
    
    func audioSessionDidEndInterruption(_ audioSession: AudioSession, shouldResume: Bool) {
        
    }
    
    func audioSession(_ audioSession: AudioSession, didChangeRouteFrom previousRoute: AVAudioSessionRouteDescription, reason: AVAudioSession.RouteChangeReason) {
        
    }
    
    func audioSessionMediaServicesWereReset(_ audioSession: AudioSession) {
        
    }
    
}
#endif
