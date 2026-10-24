#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
import AppKit
#endif

// key -> playerId
// value -> OggOpusPlayer
private var playerDictionary: [Int: OggOpusPlayer] = [:]

private var recorderDictionary: [Int: OggOpusRecorder] = [:]

public class OggOpusPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #elseif os(macOS)
    let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "ogg_record_player", binaryMessenger: messenger)
    let instance = OggOpusPlayerPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    RemoteAudioCache.shared.purgeExpiredFiles()
  }

  let channel: FlutterMethodChannel

  public init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  private func handlePlayerStateChanged(id: Int, _ player: OggOpusPlayer) {
    channel.invokeMethod("onPlayerStateChanged", arguments: [
      "state": player.status.rawValue,
      "position": player.currentTime,
      "playerId": id,
      "speed": player.playRate,
    ])
  }

  /// Registers a created player; `make` throws when the source cannot be opened.
  private func registerPlayer(result: @escaping FlutterResult, onFailure: (() -> Void)? = nil,
                              make: () throws -> OggOpusPlayer) {
    do {
      let player = try make()
      let id = generatedPlayerId()
      player.onStatusChanged = { _ in
        self.handlePlayerStateChanged(id: id, player)
      }
      playerDictionary[id] = player
      result(id)
    } catch {
      onFailure?()
      result(PlayerError.from(error).flutterError(details: error.localizedDescription))
    }
  }

  private func createFromFile(path: String, result: @escaping FlutterResult, onFailure: (() -> Void)? = nil) {
    guard FileManager.default.fileExists(atPath: path) else {
      result(PlayerError.fileNotFound.flutterError(details: path))
      return
    }
    registerPlayer(result: result, onFailure: onFailure, make: { try OggOpusPlayer(path: path) })
  }

  private func createFromUrl(_ url: URL, result: @escaping FlutterResult) {
    RemoteAudioCache.shared.localFile(for: url) { download in
      switch download {
      case let .success(file):
        self.createFromFile(path: file.path, result: result) {
          // Not a playable Ogg Opus file: don't keep it, so a later attempt downloads it again.
          RemoteAudioCache.shared.removeCachedFile(for: url)
        }
      case let .failure(error):
        result(PlayerError.from(error).flutterError(details: error.localizedDescription))
      }
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createFromFile":
      guard let path = call.arguments as? String, !path.isEmpty else {
        result(PlayerError.invalidArgument.flutterError(details: "path must be a non-empty string"))
        break
      }
      createFromFile(path: path, result: result)
    case "createFromUrl":
      guard let string = call.arguments as? String, let url = URL(string: string), RemoteAudioCache.isRemote(url) else {
        result(PlayerError.invalidArgument.flutterError(details: "url must be an http or https URL"))
        break
      }
      createFromUrl(url, result: result)
    case "createFromBytes":
      guard let bytes = (call.arguments as? FlutterStandardTypedData)?.data, !bytes.isEmpty else {
        result(PlayerError.invalidArgument.flutterError(details: "bytes must not be empty"))
        break
      }
      guard bytes.starts(with: oggSignature) else {
        result(PlayerError.invalidFile.flutterError(details: "bytes are not an Ogg stream"))
        break
      }
      registerPlayer(result: result, make: { try OggOpusPlayer(data: bytes) })
    case "play":
      if let playerId = call.arguments as? Int {
        playerDictionary[playerId]?.play()
      }
      result(nil)
    case "pause":
      if let playerId = call.arguments as? Int {
        playerDictionary[playerId]?.pause()
      }
      result(nil)
    case "stop":
      if let playerId = call.arguments as? Int {
        playerDictionary[playerId]?.stop()
        playerDictionary.removeValue(forKey: playerId)
      }
      result(nil)
    case "getDuration":
      // Seconds, matching the Android implementation.
      if let playerId = call.arguments as? Int, let player = playerDictionary[playerId] {
        result(Int(player.duration))
      } else {
        result(nil)
      }
    case "setPlaybackSpeed":
      if let args = call.arguments as? [String: Any],
         let playerId = args["playerId"] as? Int,
         let speed = args["speed"] as? Double {
        if let player = playerDictionary[playerId] {
          player.playRate = Float(speed)
          handlePlayerStateChanged(id: playerId, player)
        }
      }
      result(nil)
    case "createRecorder":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "3", message: "recorder path can not be null", details: nil))
        break
      }

      let recorder = OggOpusRecorder(path: path)
      let id = generatedPlayerId()
      recorder.delegate = PluginOggOpusRecorderDelegate(channel: channel, recorderId: id)
      recorderDictionary[id] = recorder
      result(id)
    case "startRecord":
      if let id = call.arguments as? Int {
        recorderDictionary[id]?.record(for: TimeInterval.infinity)
      }
      result(nil)
    case "stopRecord":
      if let id = call.arguments as? Int {
        recorderDictionary[id]?.stop()
      }
      result(nil)
    case "destroyRecorder":
      if let id = call.arguments as? Int {
        recorderDictionary[id]?.cancel(for: .userInitiated)
        recorderDictionary.removeValue(forKey: id)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// Every Ogg page starts with "OggS".
private let oggSignature = Data("OggS".utf8)

/// Error codes of the `createFrom*` methods, shared with Android (`PlayerError.kt`) and mapped to `OggOpusPlayerException` in Dart.
enum PlayerError: String {
  case invalidArgument = "INVALID_ARGUMENT"
  case fileNotFound = "FILE_NOT_FOUND"
  case networkError = "NETWORK_ERROR"
  case httpError = "HTTP_ERROR"
  case invalidFile = "INVALID_FILE"
  case ioError = "IO_ERROR"
  case unknown = "UNKNOWN"

  var message: String {
    switch self {
    case .invalidArgument: return "Invalid audio source"
    case .fileNotFound: return "Audio file does not exist"
    case .networkError: return "Failed to download audio"
    case .httpError: return "Server rejected the audio request"
    case .invalidFile: return "File is not a playable Ogg Opus stream"
    case .ioError: return "Failed to store downloaded audio"
    case .unknown: return "Failed to create player"
    }
  }

  static func from(_ error: Error) -> PlayerError {
    switch error {
    case let error as RemoteAudioCache.Error:
      switch error {
      case .httpStatus: return .httpError
      case .invalidFile: return .invalidFile
      }
    case is OggOpusReader.Error:
      return .invalidFile
    case is URLError:
      return .networkError
    case let error as CocoaError where error.isFileError:
      return .ioError
    default:
      return .unknown
    }
  }

  func flutterError(details: String?) -> FlutterError {
    FlutterError(code: rawValue, message: message, details: details)
  }
}

private var _lastGeneratedId = 0

private func generatedPlayerId() -> Int {
  _lastGeneratedId += 1
  return _lastGeneratedId
}

class PluginOggOpusRecorderDelegate: OggOpusRecorderDelegate {
  let channel: FlutterMethodChannel
  let recorderId: Int

  init(channel: FlutterMethodChannel, recorderId: Int) {
    self.channel = channel
    self.recorderId = recorderId
  }

  func oggOpusRecorderIsWaitingForActivation(_ recorder: OggOpusRecorder) {
  }

  func oggOpusRecorderDidStartRecording(_ recorder: OggOpusRecorder) {
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didCancelRecordingForReason reason: OggOpusRecorder.CancelledReason, userInfo: [String: Any]?) {
    channel.invokeMethod(
      "onRecorderCanceled",
      arguments: [
        "recorderId": recorderId,
        "reason": reason.rawValue,
      ],
      result: nil
    )
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFailRecordingWithError error: Error) {
    channel.invokeMethod(
      "onRecorderStartFailed",
      arguments: [
        "error": error.localizedDescription,
        "recorderId": recorderId,
      ],
      result: nil
    )
  }

  func oggOpusRecorder(_ recorder: OggOpusRecorder, didFinishRecordingWithMetadata data: AudioMetadata) {
    debugPrint("onRecorderFinished: ")
    channel.invokeMethod("onRecorderFinished", arguments: [
      "duration": NSNumber(value: data.duration),
      "waveform": FlutterStandardTypedData(bytes: data.waveform),
      "recorderId": recorderId,
    ], result: nil)
  }

  func oggOpusRecorderDidDetectAudioSessionInterruptionEnd(_ recorder: OggOpusRecorder) {
  }
}
