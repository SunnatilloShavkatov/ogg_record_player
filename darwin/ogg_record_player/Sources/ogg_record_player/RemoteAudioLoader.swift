import Foundation

/// Downloads a fresh Ogg stream into memory for every request, without storing or reusing it.
/// Android's `RemoteAudioLoader` follows the same flow.
final class RemoteAudioLoader: NSObject {
  enum Error: Swift.Error, LocalizedError {
    case httpStatus(Int)
    case invalidFile
    case tooLarge

    var errorDescription: String? {
      switch self {
      case let .httpStatus(code):
        return "Download failed with HTTP status \(code)"
      case .invalidFile:
        return "Downloaded file is not an Ogg stream"
      case .tooLarge:
        return "Download is larger than \(RemoteAudioLoader.maxBytes) bytes"
      }
    }
  }

  typealias Completion = (Result<Data, Swift.Error>) -> Void

  static let shared = RemoteAudioLoader()

  /// Largest accepted download; the Android loader enforces the same limit.
  static let maxBytes = 32 * 1024 * 1024

  /// State of one request. Only touched on `delegateQueue`.
  private final class Download {
    let completion: Completion
    var data = Data()
    var failure: Swift.Error?

    init(completion: @escaping Completion) {
      self.completion = completion
    }
  }

  private let delegateQueue: OperationQueue
  private var downloads: [Int: Download] = [:]
  private var session: URLSession!

  private override init() {
    delegateQueue = OperationQueue()
    delegateQueue.name = "uz.plugin.ogg_record_player.download"
    // Serial, so the delegate callbacks of all downloads never run concurrently.
    delegateQueue.maxConcurrentOperationCount = 1
    super.init()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.httpMaximumConnectionsPerHost = 4
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
  }

  static func isRemote(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return scheme == "https" || scheme == "http"
  }

  /// Calls `completion` on the main queue with the downloaded bytes.
  func load(_ url: URL, completion: @escaping Completion) {
    var request = URLRequest(url: url)
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    let task = session.dataTask(with: request)
    task.priority = URLSessionTask.highPriority
    // Registered on the delegate queue, ahead of any callback the resumed task can produce.
    delegateQueue.addOperation {
      self.downloads[task.taskIdentifier] = Download(completion: completion)
      task.resume()
    }
  }
}

extension RemoteAudioLoader: URLSessionDataDelegate {
  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let download = downloads[dataTask.taskIdentifier] else {
      completionHandler(.cancel)
      return
    }
    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
      download.failure = Error.httpStatus(http.statusCode)
      completionHandler(.cancel)
    } else if response.expectedContentLength > Int64(RemoteAudioLoader.maxBytes) {
      download.failure = Error.tooLarge
      completionHandler(.cancel)
    } else {
      completionHandler(.allow)
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard let download = downloads[dataTask.taskIdentifier], download.failure == nil else {
      return
    }
    // The length header can be missing or wrong, so the size is enforced while the bytes arrive.
    if download.data.count + data.count > RemoteAudioLoader.maxBytes {
      download.failure = Error.tooLarge
      dataTask.cancel()
    } else {
      download.data.append(data)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
    guard let download = downloads.removeValue(forKey: task.taskIdentifier) else {
      return
    }
    let result: Result<Data, Swift.Error>
    if let failure = download.failure {
      result = .failure(failure)
    } else if let error = error {
      result = .failure(error)
    } else if download.data.starts(with: Data("OggS".utf8)) {
      result = .success(download.data)
    } else {
      result = .failure(Error.invalidFile)
    }
    DispatchQueue.main.async { download.completion(result) }
  }
}
