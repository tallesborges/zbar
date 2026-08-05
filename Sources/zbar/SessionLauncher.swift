import AppKit

/// Opens a full interactive zdx session in a throwaway directory — the
/// replacement for the old Raycast temp-folder command.
///
/// Prefers zmux via its `zmux://` URL scheme. Falls back to a generated
/// `.command` file, which macOS routes to whatever app owns that association, so
/// neither path needs Automation permission.
enum SessionLauncher {
    static func launch(zdx: URL, seed: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zbar-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // zdx's TUI accepts no initial prompt, so anything already typed is left
        // in the session directory instead of being thrown away.
        var note = ""
        if let seed, !seed.isEmpty {
            try seed.write(to: dir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)
            note = "echo 'Your note is in prompt.md'\n"
        }

        let command = "\(shellQuoted(zdx.path)) --root \(shellQuoted(dir.path))"
        if openInZmux(directory: dir, command: command) {
            Log.info("opened zdx session in zmux at \(dir.path)")
            return dir
        }

        let script = dir.appendingPathComponent("session.command")
        let contents = """
        #!/bin/zsh
        cd \(shellQuoted(dir.path))
        \(note)exec \(command)
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        NSWorkspace.shared.open(script)
        Log.info("opened zdx session via .command at \(dir.path)")
        return dir
    }

    private static func openInZmux(directory: URL, command: String) -> Bool {
        var components = URLComponents()
        components.scheme = "zmux"
        components.host = "new"
        components.queryItems = [
            URLQueryItem(name: "cwd", value: directory.path),
            URLQueryItem(name: "cmd", value: command),
        ]

        guard let url = components.url,
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        else { return false }

        return NSWorkspace.shared.open(url)
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
