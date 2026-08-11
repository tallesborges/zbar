import Foundation

/// A preset prompt applied to selected text.
///
/// Actions are Markdown files with YAML-ish frontmatter, mirroring how zdx
/// discovers subagents from `$ZDX_HOME/subagents/*.md` — same field names, so
/// the two feel like one system. The body is the prompt; the selected text is
/// appended under a `TEXT:` heading.
struct TextAction {
    let name: String
    let description: String
    let instructions: String
    /// Model spec, `provider:model[@thinking][@fast]`. The reasoning level rides
    /// on the spec itself, so there is no separate field for it.
    let model: String?
    /// Whether the result is meant to stand in for the original selection.
    let replaces: Bool

    func prompt(for text: String) -> String {
        "\(instructions)\n\nTEXT:\n\(text)"
    }

    var row: PickerRow {
        PickerRow(title: name, subtitle: description)
    }

    /// Case-insensitive match across the fields a user would type.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = "\(name) \(description)".lowercased()
        // Every whitespace-separated term must appear, so "fix english" narrows.
        return query.lowercased().split(separator: " ").allSatisfy { haystack.contains($0) }
    }

    /// `$ZDX_HOME/zbar/actions`, falling back to `~/.zdx` when unset.
    static var directory: URL {
        let home = ProcessInfo.processInfo.environment["ZDX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zdx")
        return home.appendingPathComponent("zbar/actions", isDirectory: true)
    }

    /// Reads every action from disk, seeding the defaults on first run. Called
    /// each time the picker opens, so edits apply without restarting zbar.
    static func loadAll() -> [TextAction] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            seedDefaults()
        }

        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        let actions = files.compactMap(parse)
        return actions.isEmpty ? defaults : actions
    }

    private static func parse(_ url: URL) -> TextAction? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let (fields, body) = Frontmatter.split(raw)

        let instructions = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else {
            Log.error("action \(url.lastPathComponent) has no prompt body; skipping")
            return nil
        }

        return TextAction(
            name: fields["name"] ?? prettify(url.deletingPathExtension().lastPathComponent),
            description: fields["description"] ?? "",
            instructions: instructions,
            model: fields["model"],
            replaces: fields["replaces"].map { $0 == "true" } ?? true
        )
    }

    /// `2-explain-in-portuguese` becomes `Explain in portuguese`; a leading
    /// sort prefix is dropped so filenames can control picker order.
    private static func prettify(_ stem: String) -> String {
        let withoutPrefix = stem.drop { $0.isNumber || $0 == "-" || $0 == "_" }
        let spaced = withoutPrefix.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private static func seedDefaults() {
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
        else { return }

        for (index, action) in defaults.enumerated() {
            let slug = action.name.lowercased().replacingOccurrences(of: " ", with: "-")
            let file = directory.appendingPathComponent("\(index + 1)-\(slug).md")
            let contents = """
            ---
            name: \(action.name)
            description: \(action.description)
            replaces: \(action.replaces)
            # model: claude-cli:claude-opus-5@medium
            ---
            \(action.instructions)
            """
            try? contents.write(to: file, atomically: true, encoding: .utf8)
        }
        Log.info("seeded \(defaults.count) default actions in \(directory.path)")
    }

    // MARK: - Defaults

    static let defaults: [TextAction] = [proofread, translate, explainInPortuguese]

    static let proofread = TextAction(
        name: "Prof-read",
        description: "Fix grammar and spelling, keep the meaning",
        instructions: """
        Proofread the text below. Correct grammar, spelling, and punctuation, and \
        fix awkward phrasing. Preserve the original meaning, tone, register, and \
        language — do not translate it and do not make it more formal than it was. \
        Reply with the corrected text only: no commentary, no quotes, no explanation.
        """,
        model: nil,
        replaces: true
    )

    static let translate = TextAction(
        name: "Translate",
        description: "English ↔ Brazilian Portuguese",
        instructions: """
        Translate the text below. If it is in English, translate it to Brazilian \
        Portuguese. Otherwise, translate it to English. Preserve tone and register. \
        Reply with the translation only: no commentary, no quotes, no explanation.
        """,
        model: nil,
        replaces: true
    )

    static let explainInPortuguese = TextAction(
        name: "Explain in Portuguese",
        description: "What it means, plus vocabulary worth learning",
        instructions: """
        Explain the text below in Brazilian Portuguese, clearly and concisely. Say \
        what it means and what it implies. If it contains English vocabulary, idioms, \
        or phrasal verbs worth learning, list them briefly at the end with short \
        Portuguese glosses. Reply in Brazilian Portuguese.
        """,
        model: nil,
        replaces: false
    )
}

/// Minimal frontmatter reader: a leading `---` block of flat `key: value` pairs.
///
/// Deliberately not a YAML parser — Swift ships none, and these fields are all
/// scalars. Nested structures, lists, and multi-line values are not supported.
enum Frontmatter {
    static func split(_ raw: String) -> (fields: [String: String], body: String) {
        let lines = raw.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              })
        else { return ([:], raw) }

        var fields: [String: String] = [:]
        for line in lines[1..<close] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: ":")
            else { continue }

            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty { fields[key] = value }
        }

        let body = lines[(close + 1)...].joined(separator: "\n")
        return (fields, body)
    }
}
