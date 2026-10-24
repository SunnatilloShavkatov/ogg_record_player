import Foundation

/// Downloads a fresh Ogg stream into memory for every request, without storing or reusing it.
/// Android's `RemoteAudioLoader` follows the same flow.
final class RemoteAudioLoader {
  enum Error: Swift.Error, LocalizedError {
    case httpStatus(Int)
    case invalidFile

    var errorDescription: String? {
      switch self {
      case let .httpStatus(code):
        return "Download failed with HTTP status \(code)"
      case .invalidFile:
        return "Downloaded file is not an Ogg stream"
      }
    }
  }

  typealias Completion = (Result<Data, Swift.Error>) -> Void

  static let shared = RemoteAudioLoader()

  private let session: URLSession

  private init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.httpMaximumConnectionsPerHost = 4
    session = URLSession(configuration: configuration)
  }

  static func isRemote(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return scheme == "https" || scheme == "http"
  }

  /// Calls `completion` on the main queue with the downloaded bytes.
  func load(_ url: URL, completion: @escaping Completion) {
    var request = URLRequest(url: url)
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    let task = session.dataTask(with: request) { data, response, error in
      let result: Result<Data, Swift.Error>
      if let error = error {
        result = .failure(error)
      } else if let response = response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
        result = .failure(Error.httpStatus(response.statusCode))
      } else if let data = data {
        if data.starts(with: Data("OggS".utf8)) {
          result = .success(data)
        } else {
          result = .failure(Error.invalidFile)
        }
      } else {
        result = .failure(URLError(.badServerResponse))
      }
      DispatchQueue.main.async { completion(result) }
    }
    task.priority = URLSessionTask.highPriority
    task.resume()
  }
}
