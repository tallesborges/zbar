import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum ShellError: LocalizedError {
    case launchFailed(String)
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(detail): return "Failed to launch process: \(detail)"
        case let .timedOut(seconds): return "Timed out after \(seconds)s."
        }
    }
}

enum Shell {
    /// Mutable state shared by the pipe readers, the termination handler, and
    /// the timeout — all of which run concurrently on different queues.
    ///
    /// A continuation may only be resumed once, and the process can exit before
    /// its pipes reach EOF, so completion is only signalled once all three
    /// parts have reported in.
    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var outBuffer = Data()
        private var stdoutText = ""
        private var stderrText = ""
        private var stdoutClosed = false
        private var stderrClosed = false
        private var exitStatus: Int32?

        /// Appends stdout bytes and returns any newly completed lines.
        func appendStdout(_ data: Data) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            outBuffer.append(data)
            stdoutText += String(data: data, encoding: .utf8) ?? ""

            var lines: [String] = []
            while let newline = outBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let raw = outBuffer.subdata(in: outBuffer.startIndex..<newline)
                outBuffer.removeSubrange(outBuffer.startIndex...newline)
                if let line = String(data: raw, encoding: .utf8), !line.isEmpty {
                    lines.append(line)
                }
            }
            return lines
        }

        func appendStderr(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            stderrText += String(data: data, encoding: .utf8) ?? ""
        }

        func closeStdout() { lock.lock(); stdoutClosed = true; lock.unlock() }
        func closeStderr() { lock.lock(); stderrClosed = true; lock.unlock() }
        func setExit(_ status: Int32) { lock.lock(); exitStatus = status; lock.unlock() }

        /// Returns the result exactly once, and only when the process has
        /// exited and both pipes have hit EOF.
        func takeResultIfComplete() -> ShellResult? {
            lock.lock()
            defer { lock.unlock() }
            guard !finished, stdoutClosed, stderrClosed, let exitStatus else { return nil }
            finished = true
            return ShellResult(status: exitStatus, stdout: stdoutText, stderr: stderrText)
        }

        /// Claims the right to resume with a failure, if nothing else did.
        func takeFailure() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }
    }

    /// Runs an executable directly (no shell), so arguments never need quoting.
    ///
    /// `onLine` receives each complete stdout line as it arrives, which is what
    /// lets a caller render a streaming answer instead of waiting for exit. It
    /// is called on a background queue, in order.
    static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval = 120,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let state = RunState()
            @Sendable func finishIfComplete() {
                if let result = state.takeResultIfComplete() {
                    continuation.resume(returning: result)
                }
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    state.closeStdout()
                    finishIfComplete()
                    return
                }
                for line in state.appendStdout(data) { onLine?(line) }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    state.closeStderr()
                    finishIfComplete()
                    return
                }
                state.appendStderr(data)
            }

            process.terminationHandler = { proc in
                state.setExit(proc.terminationStatus)
                finishIfComplete()
            }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if state.takeFailure() {
                    continuation.resume(throwing: ShellError.launchFailed(error.localizedDescription))
                }
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                if state.takeFailure() {
                    continuation.resume(throwing: ShellError.timedOut(seconds: Int(timeout)))
                }
            }
        }
    }

    /// Runs a command through a login shell. Only used to resolve PATH-dependent
    /// lookups, since a GUI app inherits a minimal environment.
    static func runLoginShell(_ command: String, timeout: TimeInterval = 15) async throws -> ShellResult {
        try await run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", command],
            timeout: timeout
        )
    }
}
