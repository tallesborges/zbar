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
    /// A continuation may only be resumed once, but both the termination handler
    /// and the timeout can fire. This box holds the guard flag across the two
    /// concurrently-executing closures.
    private final class ResumeGuard: @unchecked Sendable {
        var finished = false
    }

    /// Runs an executable directly (no shell), so arguments never need quoting.
    static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval = 120
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let lock = NSLock()
            let box = ResumeGuard()
            @Sendable func finishOnce(_ body: () -> Void) {
                lock.lock()
                let already = box.finished
                box.finished = true
                lock.unlock()
                if !already { body() }
            }

            process.terminationHandler = { proc in
                let out = String(
                    data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
                let err = String(
                    data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
                finishOnce {
                    continuation.resume(
                        returning: ShellResult(status: proc.terminationStatus, stdout: out, stderr: err)
                    )
                }
            }

            do {
                try process.run()
            } catch {
                finishOnce {
                    continuation.resume(throwing: ShellError.launchFailed(error.localizedDescription))
                }
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                finishOnce {
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
