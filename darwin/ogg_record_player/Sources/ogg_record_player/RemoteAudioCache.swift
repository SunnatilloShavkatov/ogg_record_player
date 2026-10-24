import CryptoKit
import Foundation

/// Downloads remote (`http`/`https`) Ogg Opus files into the Caches directory so `OggOpusReader` can open them
/// like local files. A download is reused for `maxAge`, then fetched again; concurrent requests for the same URL
/// share one download. The Android `RemoteAudioCache` follows the same flow and file layout.
final class RemoteAudioCache {
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

  typealias Completion = (Result<URL, Swift.Error>) -> Void

  static let shared = RemoteAudioCache()

  /// Cached files older than this are deleted and downloaded again.
  static let maxAge: TimeInterval = 7 * 24 * 60 * 60

  private let session: URLSession
  private let directory: URL
  private let ioQueue = DispatchQueue(label: "ogg_record_player.cache", qos: .utility)

  /// Pending completions per remote URL. Accessed on the main queue only.
  private var pending: [URL: [Completion]] = [:]

  private init() {
    let configuration = URLSessionConfiguration.default
    // Downloaded files are kept in `directory`; storing them in URLCache too would only duplicate them.
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.httpMaximumConnectionsPerHost = 4
    session = URLSession(configuration: configuration)

    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    directory = caches.appendingPathComponent("ogg_record_player", isDirectory: true)
  }

  static func isRemote(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return scheme == "https" || scheme == "http"
  }

  /// Deletes expired files in the background. Called once when the plugin registers.
  func purgeExpiredFiles() {
    ioQueue.async { [directory] in
      let fileManager = FileManager.default
      guard let files = try? fileManager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: [.contentModificationDateKey],
                                                             options: .skipsHiddenFiles) else {
        return
      }
      for file in files where RemoteAudioCache.isExpired(file) {
        try? fileManager.removeItem(at: file)
      }
    }
  }

  /// Calls `completion` on the main queue with a local file holding the contents of `url`.
  func localFile(for url: URL, completion: @escaping Completion) {
    assert(Thread.isMainThread)
    if pending[url] != nil {
      pending[url]?.append(completion)
      return
    }
    pending[url] = [completion]

    let destination = cachedFileURL(for: url)
    // The cache lookup touches the disk, so it stays off the main thread like the download itself.
    ioQueue.async {
      if FileManager.default.fileExists(atPath: destination.path), !RemoteAudioCache.isExpired(destination) {
        DispatchQueue.main.async { self.finish(url, with: .success(destination)) }
      } else {
        self.download(url, to: destination)
      }
    }
  }

  /// Deletes the cached copy of `url`, e.g. when it turned out not to be a playable Ogg Opus file.
  func removeCachedFile(for url: URL) {
    let file = cachedFileURL(for: url)
    ioQueue.async {
      try? FileManager.default.removeItem(at: file)
    }
  }

  private func download(_ url: URL, to destination: URL) {
    let task = session.downloadTask(with: url) { [directory] location, response, error in
      // `location` is deleted when this handler returns, so it is moved into the cache here.
      let result: Result<URL, Swift.Error>
      if let error = error {
        result = .failure(error)
      } else if let response = response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
        result = .failure(Error.httpStatus(response.statusCode))
      } else if let location = location {
        do {
          guard RemoteAudioCache.hasOggSignature(location) else {
            throw Error.invalidFile
          }
          let fileManager = FileManager.default
          try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
          if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
          }
          try fileManager.moveItem(at: location, to: destination)
          // The age is counted from the download, whatever date the temporary file carried.
          try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
          result = .success(destination)
        } catch {
          result = .failure(error)
        }
      } else {
        result = .failure(URLError(.badServerResponse))
      }
      DispatchQueue.main.async {
        self.finish(url, with: result)
      }
    }
    task.priority = URLSessionTask.highPriority
    task.resume()
  }

  private func cachedFileURL(for url: URL) -> URL {
    let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
    let name = digest.map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name).appendingPathExtension("ogg")
  }

  private func finish(_ url: URL, with result: Result<URL, Swift.Error>) {
    let completions = pending.removeValue(forKey: url) ?? []
    for completion in completions {
      completion(result)
    }
  }

  private static func isExpired(_ file: URL) -> Bool {
    guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
      return true
    }
    return Date().timeIntervalSince(date) > maxAge
  }

  /// Every Ogg page starts with "OggS"; checking it rejects HTML error pages served with a 200 status.
  private static func hasOggSignature(_ file: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: file) else {
      return false
    }
    defer { try? handle.close() }
    return handle.readData(ofLength: 4) == Data("OggS".utf8)
  }
}
