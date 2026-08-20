import Foundation

// MARK: - stdout/stderr capture helpers
//
// We redirect the live POSIX FD into a temporary file (not a pipe) so the
// Swift Testing framework's own output written during the captured block
// can drain freely without blocking the writer side, and we can read the
// captured slice back after restoring the FD. Using a Pipe here deadlocks
// once the pipe buffer fills because Swift Testing keeps writing to the
// redirected FD throughout the test run.

/// Process-wide lock ensuring FD redirects are serialized across all test
/// suites. Without this, parallel tests could redirect the same global FD
/// concurrently and corrupt each other's captures.
let fdCaptureLock = NSLock()

func captureStdout(_ block: () throws -> Void) throws -> String {
    try captureFD(STDOUT_FILENO, block)
}

func captureStderr(_ block: () throws -> Void) throws -> String {
    try captureFD(STDERR_FILENO, block)
}

func captureFD(_ fd: Int32, _ block: () throws -> Void) throws -> String {
    fdCaptureLock.lock()
    defer { fdCaptureLock.unlock() }

    let saved = dup(fd)
    defer { close(saved) }

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("aidash-capture-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
    let writeHandle = try FileHandle(forWritingTo: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    dup2(writeHandle.fileDescriptor, fd)

    var thrown: Error?
    do {
        try block()
    } catch {
        thrown = error
    }

    // Flush + restore.
    try? writeHandle.synchronize()
    dup2(saved, fd)
    try? writeHandle.close()

    let captured = (try? String(contentsOf: tmpURL, encoding: .utf8)) ?? ""
    if let thrown { throw thrown }
    return captured
}
