import AVFoundation
import Foundation
#if os(iOS)
import UIKit
#endif

/// The microphone permission, as the shared status codes of Dart's `MicrophonePermission` and Android's
/// `MicrophonePermission`. iOS asks only once: a refusal can be undone only in Settings, so it is permanent.
extension OggRecordPlayerApi {
  static let permissionGranted = 0
  static let permissionPermanentlyDenied = 2
  static let permissionUndetermined = 3

  @objc public static func microphonePermission() -> Int {
    #if os(iOS)
    if #available(iOS 17.0, *) {
      switch AVAudioApplication.shared.recordPermission {
      case .granted: return permissionGranted
      case .denied: return permissionPermanentlyDenied
      default: return permissionUndetermined
      }
    }
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted: return permissionGranted
    case .denied: return permissionPermanentlyDenied
    default: return permissionUndetermined
    }
    #else
    return permissionGranted
    #endif
  }

  /// Shows the system prompt the first time; afterwards answers the known status at once. Answers on main.
  @objc(requestMicrophonePermission:)
  public static func requestMicrophonePermission(_ callback: @escaping (Int) -> Void) {
    let answer: (Bool) -> Void = { _ in DispatchQueue.main.async { callback(microphonePermission()) } }
    #if os(iOS)
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: answer)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(answer)
    }
    #else
    answer(true)
    #endif
  }

  /// Opens this app's page in Settings, where a refused microphone permission can be granted.
  @objc public static func openAppSettings() -> Bool {
    #if os(iOS)
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
    DispatchQueue.main.async { UIApplication.shared.open(url) }
    return true
    #else
    return false
    #endif
  }
}
