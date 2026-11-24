import Foundation

/// Runs `work` on the main thread, inline when already there.
func onMainSync<T>(execute work: () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        return try work()
    }
    return try DispatchQueue.main.sync(execute: work)
}

/// Runs `work` on the main thread, inline when already there, otherwise asynchronously.
func onMainAsync(execute work: @escaping () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
