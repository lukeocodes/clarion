import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ServiceProvider()
    private var onboardingWindow: NSWindow?
    private var onboardingBridge: WebBridge?
    private var settingsWindow: NSWindow?
    private var settingsBridge: WebBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()

        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettings),
            name: NSNotification.Name("ShowSettings"), object: nil
        )

        // Load saved hotkey and wire callback
        HotkeyManager.shared.onHotkey = { [weak self] in
            self?.hotkeyTriggered()
        }
        HotkeyManager.shared.loadSaved()

        if KeychainManager.getAPIKey() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showOnboarding()
            }
        }
    }

    // MARK: - Hotkey Callback

    private func hotkeyTriggered() {
        guard HotkeyManager.isAccessibilityTrusted else {
            HotkeyManager.requestAccessibility()
            return
        }
        HotkeyManager.shared.getSelectedText { text in
            guard let text else { return }
            Task { @MainActor in
                SpeechManager.shared.speak(text)
            }
        }
    }

    // MARK: - Onboarding

    func showOnboarding() {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let bridge = WebBridge(htmlFileName: "onboarding")
        bridge.onAction = { [weak self] action, body in
            self?.handleOnboardingAction(action, body: body)
        }

        let window = makeWindow(title: "Clarion Setup", width: 440, height: 480, view: bridge.webView)
        self.onboardingWindow = window
        self.onboardingBridge = bridge
    }

    private func handleOnboardingAction(_ action: String, body: [String: Any]) {
        let apiKey = body["apiKey"] as? String ?? ""

        switch action {
        case "testKey":
            onboardingBridge?.evaluateJS("updateState({testResult:'testing'})")
            Task { @MainActor in
                let ok = await SpeechManager.shared.testConnection(apiKey: apiKey)
                self.onboardingBridge?.evaluateJS("updateState({testResult:'\(ok ? "success" : "failure")'})")
            }

        case "saveKey":
            let saved = KeychainManager.save(apiKey: apiKey)
            if saved {
                let enabled = isServiceEnabled()
                onboardingBridge?.evaluateJS("updateState({keySaved:true,serviceEnabled:\(enabled)})")
            }

        case "openURL":
            if let urlStr = body["url"] as? String, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }

        case "openSystemPrefs":
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }

        case "checkService":
            let enabled = isServiceEnabled()
            onboardingBridge?.evaluateJS("updateState({serviceEnabled:\(enabled)})")

        case "dismiss":
            onboardingWindow?.close()
            onboardingWindow = nil
            onboardingBridge = nil

        default:
            break
        }
    }

    // MARK: - Settings

    @objc func showSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let bridge = WebBridge(htmlFileName: "settings")
        bridge.onAction = { [weak self] action, body in
            self?.handleSettingsAction(action, body: body)
        }

        let window = makeWindow(title: "Clarion Settings", width: 440, height: 500, view: bridge.webView)
        window.delegate = self
        self.settingsWindow = window
        self.settingsBridge = bridge

        // Push current state to the HTML after a brief load delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let key = KeychainManager.getAPIKey() ?? ""
            let model = SpeechManager.shared.voiceModel
            let escaped = key.replacingOccurrences(of: "'", with: "\\'")
            let enabled = self.isServiceEnabled()
            let shortcut = HotkeyManager.shared.savedDisplay ?? ""
            let shortcutEscaped = shortcut.replacingOccurrences(of: "'", with: "\\'")
            let accessible = HotkeyManager.isAccessibilityTrusted
            bridge.evaluateJS("updateState({apiKey:'\(escaped)',voiceModel:'\(model)',serviceEnabled:\(enabled),shortcutDisplay:'\(shortcutEscaped)',accessibilityTrusted:\(accessible)})")
        }
    }

    private func handleSettingsAction(_ action: String, body: [String: Any]) {
        let apiKey = body["apiKey"] as? String ?? ""

        switch action {
        case "saveKey":
            let saved = KeychainManager.save(apiKey: apiKey)
            settingsBridge?.evaluateJS("updateState({keySaved:\(saved)})")

        case "clearKey":
            KeychainManager.delete()
            settingsBridge?.evaluateJS("updateState({keyCleared:true})")

        case "setVoiceModel":
            if let model = body["model"] as? String {
                Task { @MainActor in
                    SpeechManager.shared.voiceModel = model
                }
            }

        case "testVoice":
            settingsBridge?.evaluateJS("updateState({voiceTest:'testing'})")
            let key = apiKey.isEmpty ? (KeychainManager.getAPIKey() ?? "") : apiKey
            let model = body["model"] as? String
            if let model {
                Task { @MainActor in
                    SpeechManager.shared.voiceModel = model
                }
            }
            Task { @MainActor in
                guard let wav = await SpeechManager.shared.fetchTestAudio(apiKey: key, model: model) else {
                    self.settingsBridge?.evaluateJS("updateState({voiceTest:'failure'})")
                    return
                }
                let b64 = wav.base64EncodedString()
                self.settingsBridge?.evaluateJS("updateState({voiceTest:'success',audioData:'\(b64)'})")
            }

        case "openURL":
            if let urlStr = body["url"] as? String, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }

        case "openSystemPrefs":
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }

        case "checkService":
            let enabled = isServiceEnabled()
            settingsBridge?.evaluateJS("updateState({serviceEnabled:\(enabled)})")

        case "saveShortcut":
            if let code = body["code"] as? String,
               let carbonKey = HotkeyManager.carbonKeyCode(from: code) {
                let cmd = body["cmd"] as? Bool ?? false
                let shift = body["shift"] as? Bool ?? false
                let option = body["option"] as? Bool ?? false
                let control = body["control"] as? Bool ?? false
                let display = body["display"] as? String ?? ""
                let mods = HotkeyManager.carbonModifiers(cmd: cmd, shift: shift, option: option, control: control)
                HotkeyManager.shared.save(keyCode: carbonKey, modifiers: mods, display: display)
                let accessible = HotkeyManager.isAccessibilityTrusted
                settingsBridge?.evaluateJS("updateState({shortcutDisplay:'\(display)',accessibilityTrusted:\(accessible)})")
                if !accessible {
                    HotkeyManager.requestAccessibility()
                }
            }

        case "clearShortcut":
            HotkeyManager.shared.clear()
            settingsBridge?.evaluateJS("updateState({shortcutDisplay:''})")

        case "checkShortcut":
            let display = HotkeyManager.shared.savedDisplay ?? ""
            let escaped = display.replacingOccurrences(of: "'", with: "\\'")
            let accessible = HotkeyManager.isAccessibilityTrusted
            settingsBridge?.evaluateJS("updateState({shortcutDisplay:'\(escaped)',accessibilityTrusted:\(accessible)})")

        case "requestAccessibility":
            HotkeyManager.requestAccessibility()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let accessible = HotkeyManager.isAccessibilityTrusted
                self.settingsBridge?.evaluateJS("updateState({accessibilityTrusted:\(accessible)})")
            }

        case "dismiss":
            settingsWindow?.close()
            settingsWindow = nil
            settingsBridge = nil

        default:
            break
        }
    }

    // MARK: - Service Status

    private func isServiceEnabled() -> Bool {
        guard let pbs = UserDefaults(suiteName: "pbs"),
              let status = pbs.dictionary(forKey: "NSServicesStatus"),
              let entry = status["com.lukeocodes.clarion - Read Aloud - readAloud"] as? [String: Any]
        else { return false }
        return entry["enabled_context_menu"] as? Bool ?? (entry["enabled_context_menu"] as? Int == 1)
    }

    // MARK: - Window Factory

    private func makeWindow(title: String, width: CGFloat, height: CGFloat, view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}

// MARK: - NSWindowDelegate (clean up settings refs on close)

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            settingsWindow = nil
            settingsBridge = nil
        }
    }
}
