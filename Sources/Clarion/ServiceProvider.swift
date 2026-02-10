import AppKit

final class ServiceProvider: NSObject {
    @objc func readAloud(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text provided" as NSString
            return
        }

        Task { @MainActor in
            SpeechManager.shared.speak(text)
        }
    }
}
