import Foundation

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
    case .ioError: return "Failed to read audio data"
    case .unknown: return "Failed to create player"
    }
  }

  static func from(_ error: Error) -> PlayerError {
    switch error {
    case let error as RemoteAudioLoader.Error:
      switch error {
      case .httpStatus: return .httpError
      case .invalidFile: return .invalidFile
      case .tooLarge: return .ioError
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
}

/// Every Ogg page starts with "OggS".
let oggSignature = Data("OggS".utf8)
