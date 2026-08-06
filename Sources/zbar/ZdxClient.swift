import Foundation

enum ZdxError: LocalizedError {
    case binaryNotFound
    case failed(status: Int32, stderr: String)
    case noText
    case speechFailed(stderr: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Could not find the `zdx` binary on your login shell PATH."
        case let .failed(status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "zdx exec failed (code \(status))."
                : "zdx exec failed (code \(status)).\n\(detail)"
        case .noText:
            return "zdx exec returned no answer text."
        case let .speechFailed(stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "zdx speak failed." : "zdx speak failed.\n\(detail)"
        }
    }
}

/// Thin wrapper over the `zdx` CLI. zbar never links the Rust crates; the CLI is
/// the entire contract.
@MainActor
final class ZdxClient {
    /// Resolved once at launch. `nil` means zdx is unavailable and the menu bar
    /// should say so rather than failing silently on every action.
    private(set) var binary: URL?
    private(set) var version: String?

    /// Resolves `zdx` through a login shell, because a GUI app launched from
    /// Finder inherits a minimal PATH that excludes ~/.local/bin.
    func resolve() async {
        do {
            let which = try await Shell.runLoginShell("command -v zdx")
            let path = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard which.status == 0, !path.isEmpty else {
                Log.error("zdx not found on login shell PATH")
                binary = nil
                return
            }

            let url = URL(fileURLWithPath: path)
            let versionResult = try await Shell.run(executable: url, arguments: ["--version"], timeout: 15)
            binary = url
            version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.info("resolved zdx at \(path) (\(version ?? "unknown version"))")
        } catch {
            Log.error("failed to resolve zdx: \(error.localizedDescription)")
            binary = nil
        }
    }

    /// Runs a prompt and returns the final answer text.
    ///
    /// Passing a `thread` continues that conversation; zdx replays the thread's
    /// history, so follow-up turns keep context. Without one the turn is
    /// isolated and nothing is persisted.
    ///
    /// The model zdx actually used on the last turn, read back from its output.
    ///
    /// Worth capturing because zbar often passes no `-m` at all, in which case
    /// only zdx knows which model the config resolved to.
    private(set) var lastModel: String?

    /// Tools and the system prompt travel together. Enabling tools without the
    /// system prompt leaves the model unaware of how to use them; keeping the
    /// system prompt without tools is worse still — it advertises skills and
    /// tools the model cannot call, so it answers with invented tool-call markup
    /// instead of text.
    ///
    /// `model` is a full zdx model spec, `provider:model[@thinking][@fast]`, so
    /// the reasoning level travels with it and needs no separate flag.
    func ask(
        prompt: String,
        root: URL? = nil,
        thread: String? = nil,
        model: String? = nil,
        thinking: String? = nil,
        tools: Bool = false,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        guard let binary else { throw ZdxError.binaryNotFound }

        let scratch: URL
        let isTemporary: Bool
        if let root {
            scratch = root
            isTemporary = false
        } else {
            scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("zbar-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            isTemporary = true
        }
        defer { if isTemporary { try? FileManager.default.removeItem(at: scratch) } }

        var arguments = ["--root", scratch.path]
        if let thread {
            arguments.append(contentsOf: ["--thread", thread])
        } else {
            arguments.append("--no-thread")
        }
        arguments.append("exec")
        if !tools { arguments.append(contentsOf: ["--no-tools", "--no-system-prompt"]) }
        if let model { arguments.append(contentsOf: ["-m", model]) }
        // `-t` rather than an `@` suffix, because a level can be chosen while
        // the model is left at the zdx default, where there is no spec to
        // append to. It also wins over any suffix already on the spec.
        if let thinking { arguments.append(contentsOf: ["-t", thinking]) }
        arguments.append(contentsOf: ["-p", prompt])

        // A tool-using turn can take several round trips, so it gets more room.
        let deadline = timeout ?? (tools ? 300 : 120)
        let result = try await Shell.run(executable: binary, arguments: arguments, timeout: deadline)
        guard result.status == 0 else {
            throw ZdxError.failed(status: result.status, stderr: result.stderr)
        }
        lastModel = Self.usedModel(from: result.stdout)
        guard let text = Self.finalText(from: result.stdout), !text.isEmpty else {
            throw ZdxError.noText
        }
        return text
    }

    /// `usage_update` events carry the resolved `provider` and `model`.
    static func usedModel(from stdout: String) -> String? {
        for line in stdout.split(separator: "\n").reversed() {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["type"] as? String == "usage_update",
                let model = object["model"] as? String
            else { continue }

            if let provider = object["provider"] as? String, !provider.isEmpty {
                return "\(provider):\(model)"
            }
            return model
        }
        return nil
    }

    /// Synthesizes `text` to an audio file and returns its path.
    ///
    /// Format is forced to mp3: the configured default is tuned for Telegram
    /// voice notes (ogg/opus), which `AVAudioPlayer` will not play. Voice and
    /// model deliberately come from the user's zdx config.
    func speak(_ text: String, timeout: TimeInterval = 120) async throws -> URL {
        guard let binary else { throw ZdxError.binaryNotFound }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("zbar-speech-\(UUID().uuidString).mp3")

        let result = try await Shell.run(
            executable: binary,
            arguments: ["speak", text, "--out", out.path, "--format", "mp3"],
            timeout: timeout
        )
        guard result.status == 0 else {
            throw ZdxError.speechFailed(stderr: result.stderr)
        }
        guard FileManager.default.fileExists(atPath: out.path) else {
            throw ZdxError.speechFailed(stderr: "zdx speak wrote no audio file.")
        }
        return out
    }

    /// `zdx exec` emits JSON Lines. The authoritative answer is `final_text` on
    /// the `turn_finished` event; `assistant_completed.text` is an earlier echo
    /// of the same string and serves as a fallback.
    static func finalText(from stdout: String) -> String? {
        var fallback: String?

        for line in stdout.split(separator: "\n") {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else { continue }

            switch type {
            case "turn_finished":
                if let text = object["final_text"] as? String {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "assistant_completed":
                if let text = object["text"] as? String {
                    fallback = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            default:
                continue
            }
        }

        return fallback
    }
}
