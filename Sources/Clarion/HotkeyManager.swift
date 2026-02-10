import AppKit
import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onHotkey: (() -> Void)?

    private init() {}

    // MARK: - Registration

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                mgr.onHotkey?()
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef
        )

        let hotkeyID = EventHotKeyID(signature: 0x434C524E, id: 1) // "CLRN"
        RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    // MARK: - Selected Text (via simulated Cmd+C)

    func getSelectedText(completion: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)

        pb.clearContents()

        // Simulate Cmd+C
        let src = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true) // 'c' key
        down?.flags = CGEventFlags.maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        up?.flags = CGEventFlags.maskCommand
        down?.post(tap: CGEventTapLocation.cghidEventTap)
        up?.post(tap: CGEventTapLocation.cghidEventTap)

        // Wait for pasteboard to update, then read
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let text = pb.string(forType: .string)

            // Restore previous clipboard
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }

            completion(text?.isEmpty == false ? text : nil)
        }
    }

    // MARK: - Accessibility

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Persistence

    private static let keyCodeKey = "shortcutKeyCode"
    private static let modifiersKey = "shortcutModifiers"
    private static let displayKey = "shortcutDisplay"

    func save(keyCode: UInt32, modifiers: UInt32, display: String) {
        UserDefaults.standard.set(Int(keyCode), forKey: Self.keyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: Self.modifiersKey)
        UserDefaults.standard.set(display, forKey: Self.displayKey)
        register(keyCode: keyCode, modifiers: modifiers)
    }

    func clear() {
        unregister()
        UserDefaults.standard.removeObject(forKey: Self.keyCodeKey)
        UserDefaults.standard.removeObject(forKey: Self.modifiersKey)
        UserDefaults.standard.removeObject(forKey: Self.displayKey)
    }

    var savedDisplay: String? {
        UserDefaults.standard.string(forKey: Self.displayKey)
    }

    func loadSaved() {
        let kc = UserDefaults.standard.integer(forKey: Self.keyCodeKey)
        let mods = UserDefaults.standard.integer(forKey: Self.modifiersKey)
        guard kc != 0 || mods != 0, savedDisplay != nil else { return }
        register(keyCode: UInt32(kc), modifiers: UInt32(mods))
    }

    // MARK: - JS Key Code → Carbon Key Code

    static func carbonKeyCode(from jsCode: String) -> UInt32? {
        let map: [String: UInt32] = [
            "KeyA": 0x00, "KeyS": 0x01, "KeyD": 0x02, "KeyF": 0x03,
            "KeyH": 0x04, "KeyG": 0x05, "KeyZ": 0x06, "KeyX": 0x07,
            "KeyC": 0x08, "KeyV": 0x09, "KeyB": 0x0B, "KeyQ": 0x0C,
            "KeyW": 0x0D, "KeyE": 0x0E, "KeyR": 0x0F, "KeyY": 0x10,
            "KeyT": 0x11, "Digit1": 0x12, "Digit2": 0x13, "Digit3": 0x14,
            "Digit4": 0x15, "Digit6": 0x16, "Digit5": 0x17, "Equal": 0x18,
            "Digit9": 0x19, "Digit7": 0x1A, "Minus": 0x1B, "Digit8": 0x1C,
            "Digit0": 0x1D, "BracketRight": 0x1E, "KeyO": 0x1F, "KeyU": 0x20,
            "BracketLeft": 0x21, "KeyI": 0x22, "KeyP": 0x23, "KeyL": 0x25,
            "KeyJ": 0x26, "Quote": 0x27, "KeyK": 0x28, "Semicolon": 0x29,
            "Backslash": 0x2A, "Comma": 0x2B, "Slash": 0x2C, "KeyN": 0x2D,
            "KeyM": 0x2E, "Period": 0x2F, "Backquote": 0x32, "Space": 0x31,
            "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76,
            "F5": 0x60, "F6": 0x61, "F7": 0x62, "F8": 0x64,
            "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
        ]
        return map[jsCode]
    }

    static func carbonModifiers(cmd: Bool, shift: Bool, option: Bool, control: Bool) -> UInt32 {
        var mods: UInt32 = 0
        if cmd { mods |= UInt32(cmdKey) }
        if shift { mods |= UInt32(shiftKey) }
        if option { mods |= UInt32(optionKey) }
        if control { mods |= UInt32(controlKey) }
        return mods
    }
}
