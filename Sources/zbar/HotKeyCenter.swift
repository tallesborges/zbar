import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon's `RegisterEventHotKey`.
///
/// Carbon is used deliberately over `NSEvent.addGlobalMonitorForEvents`, which
/// requires the Accessibility permission. Carbon hotkeys work with no TCC prompt
/// at all, which keeps quick-ask usable before zbar ever asks for permissions.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {}

    @discardableResult
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            Log.error("failed to register hotkey \(shortcut.display) (OSStatus \(status))")
            return false
        }

        actions[id] = action
        refs[id] = ref
        Log.info("registered hotkey \(shortcut.display)")
        return true
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // The callback is a bare C function pointer and cannot capture context,
        // so it looks the handler up by id on the shared singleton.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let id = hotKeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }

    private static let signature: OSType = {
        let chars = Array("zbar".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }()
}

extension HotKeyCenter {
    struct Shortcut {
        let keyCode: UInt32
        let modifiers: NSEvent.ModifierFlags
        let display: String
        /// Character AppKit uses to render this shortcut in a menu.
        let menuKeyEquivalent: String

        var carbonModifiers: UInt32 {
            var value: UInt32 = 0
            if modifiers.contains(.control) { value |= UInt32(controlKey) }
            if modifiers.contains(.option) { value |= UInt32(optionKey) }
            if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
            if modifiers.contains(.command) { value |= UInt32(cmdKey) }
            return value
        }

        /// Hardcoded for now; Polish round 2 makes this user-configurable.
        /// ⌃⌥Space avoids the ⌘Space / ⌥Space slots that Spotlight and Raycast
        /// usually occupy.
        static let quickAsk = Shortcut(
            keyCode: UInt32(kVK_Space),
            modifiers: [.control, .option],
            display: "⌃⌥Space",
            menuKeyEquivalent: " "
        )

        static let selectionAction = Shortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: [.control, .option],
            display: "⌃⌥A",
            menuKeyEquivalent: "a"
        )
    }
}
