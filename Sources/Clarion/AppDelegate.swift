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

        if KeychainManager.getAPIKey() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showOnboarding()
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
                onboardingWindow?.close()
                onboardingWindow = nil
                onboardingBridge = nil
            }

        case "openURL":
            if let urlStr = body["url"] as? String, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }

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
            bridge.evaluateJS("updateState({apiKey:'\(escaped)',voiceModel:'\(model)'})")
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

        case "dismiss":
            settingsWindow?.close()
            settingsWindow = nil
            settingsBridge = nil

        default:
            break
        }
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
