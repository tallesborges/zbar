import AppKit
import Carbon.HIToolbox

/// User settings, read from `$ZDX_HOME/zbar/config.md`.
///
/// Same frontmatter shape as the action files, so there is one format to learn.
/// Every key is optional and falls back to a built-in default.
struct Settings {
    var quickAsk: HotKeyCenter.Shortcut
    var selectionActions: HotKeyCenter.Shortcut
    /// Default model for quick ask; nil uses the zdx default.
    var model: String?
    /// Whether quick ask starts with tools and the system prompt enabled.
    var tools: Bool

    static let `default` = Settings(
        quickAsk: .defaultQuickAsk,
        selectionActions: .defaultSelectionActions,
        model: nil,
        tools: true
    )

    static var file: URL {
        TextAction.directory
            .deletingLastPathComponent()
            .appendingPathComponent("config.md")
    }

    static func load() -> Settings {
        seedIfMissing()

        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return .default }
        let (fields, _) = Frontmatter.split(raw)

        var settings = Settings.default
        if let value = fields["quick_ask"] {
            if let parsed = HotKeyCenter.Shortcut(value) {
                settings.quickAsk = parsed
            } else {
                Log.error("could not parse quick_ask shortcut '\(value)'; using the default")
            }
        }
        if let value = fields["selection_actions"] {
            if let parsed = HotKeyCenter.Shortcut(value) {
                settings.selectionActions = parsed
            } else {
                Log.error("could not parse selection_actions shortcut '\(value)'; using the default")
            }
        }
        settings.model = fields["model"]
        // Only an explicit key overrides the default, so omitting it keeps
        // tools on rather than silently turning them off.
        if let value = fields["tools"] { settings.tools = value == "true" }
        return settings
    }

    private static func seedIfMissing() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: file.path) else { return }
        try? fm.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let contents = """
        ---
        # Global shortcuts. Modifiers: ctrl, opt (alt), cmd, shift.
        # Keys: a-z, 0-9, space, return, tab, escape, comma, period, slash.
        quick_ask: \(Shortcut.defaultQuickAsk.configValue)
        selection_actions: \(Shortcut.defaultSelectionActions.configValue)

        # Default model for quick ask, as provider:model[@thinking][@fast].
        # Leave unset to use the zdx default. Change it live with shift+cmd+m.
        # model: claude-cli:claude-opus-5@medium

        # Quick ask runs the full agent: tools, skills and memory. Set to false
        # for plain, faster answers that cannot read or write files.
        # Toggle for one conversation with shift+cmd+t.
        tools: true
        ---
        zbar settings. Only the frontmatter above is read; this text is a note to self.
        """
        try? contents.write(to: file, atomically: true, encoding: .utf8)
        Log.info("seeded settings at \(file.path)")
    }

    private typealias Shortcut = HotKeyCenter.Shortcut
}

extension HotKeyCenter.Shortcut {
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    static let defaultQuickAsk = HotKeyCenter.Shortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: [.control, .option],
        display: "⌃⌥Space",
        menuKeyEquivalent: " "
    )

    static let defaultSelectionActions = HotKeyCenter.Shortcut(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: [.control, .option],
        display: "⌃⌥A",
        menuKeyEquivalent: "a"
    )

    /// Parses `ctrl+opt+space`, `cmd+shift+k`, and similar.
    init?(_ text: String) {
        var modifiers: NSEvent.ModifierFlags = []
        var key: String?

        for token in text.lowercased().split(whereSeparator: { $0 == "+" || $0 == "-" }) {
            switch token {
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "alt", "option": modifiers.insert(.option)
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            default: key = String(token)
            }
        }

        guard let key, let code = Self.keyCodes[key], !modifiers.isEmpty else { return nil }

        self.init(
            keyCode: code,
            modifiers: modifiers,
            display: Self.describe(modifiers: modifiers, key: key),
            menuKeyEquivalent: Self.menuEquivalents[key] ?? key
        )
    }

    /// Round-trips back to the config spelling, for seeding the settings file.
    var configValue: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        let key = Self.keyCodes.first { $0.value == keyCode }?.key ?? "?"
        return (parts + [key]).joined(separator: "+")
    }

    private static func describe(modifiers: NSEvent.ModifierFlags, key: String) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + (displayNames[key] ?? key.uppercased())
    }

    private static let displayNames: [String: String] = [
        "space": "Space", "return": "Return", "tab": "Tab", "escape": "Esc",
        "comma": ",", "period": ".", "slash": "/",
    ]

    private static let menuEquivalents: [String: String] = [
        "space": " ", "return": "\r", "tab": "\t", "escape": "\u{1b}",
        "comma": ",", "period": ".", "slash": "/",
    ]

    private static let keyCodes: [String: UInt32] = {
        var map: [String: UInt32] = [
            "space": UInt32(kVK_Space),
            "return": UInt32(kVK_Return),
            "tab": UInt32(kVK_Tab),
            "escape": UInt32(kVK_Escape),
            "comma": UInt32(kVK_ANSI_Comma),
            "period": UInt32(kVK_ANSI_Period),
            "slash": UInt32(kVK_ANSI_Slash),
        ]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
            ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
            ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
            ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ]
        let digits: [(String, Int)] = [
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
            ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        ]
        for (name, code) in letters + digits { map[name] = UInt32(code) }
        return map
    }()
}
