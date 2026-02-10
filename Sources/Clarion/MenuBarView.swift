import SwiftUI

struct MenuBarView: View {
    @ObservedObject var speechManager = SpeechManager.shared

    var body: some View {
        VStack(spacing: 4) {
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
            }) {
                Label("Settings...", systemImage: "gear")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.vertical, 4)

            Divider()

            Button(action: { NSApp.terminate(nil) }) {
                Label("Quit Clarion", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .padding(.bottom, 8)
        }
        .frame(width: 200)
    }
}
