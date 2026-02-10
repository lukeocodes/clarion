import SwiftUI

@main
struct ClarionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var speechManager = SpeechManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(speechManager: speechManager)
        } label: {
            Image(
                systemName: speechManager.isSpeaking
                    ? "speaker.wave.3.fill" : "speaker.wave.2"
            )
        }
    }
}
