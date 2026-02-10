import AVFoundation
import Foundation
import NaturalLanguage

@MainActor
final class SpeechManager: ObservableObject {
    static let shared = SpeechManager()

    @Published var isSpeaking = false
    @Published var isConnected = false
    @Published var voiceModel = "aura-2-thalia-en"

    // WebSocket path
    private var ttsClient: DeepgramTTSClient?
    private var audioPlayer: AudioStreamPlayer?

    // REST path
    private var wavPlayer: AVAudioPlayer?
    private var restTask: Task<Void, Never>?

    // Default voice per supported language (Aura 2 voice names are language-specific)
    private static let languageVoices: [NLLanguage: String] = [
        .french:    "aura-2-agathe-fr",
        .spanish:   "aura-2-agustina-es",
        .japanese:  "aura-2-ama-ja",
        .german:    "aura-2-aurelia-de",
        .dutch:     "aura-2-beatrix-nl",
        .italian:   "aura-2-cesare-it",
    ]

    private init() {}

    /// Detect language of text and return the appropriate voice model.
    /// Uses the user's selected voice for English, a per-language default otherwise.
    func resolveModel(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage, lang != .english else {
            return voiceModel
        }
        if let voice = Self.languageVoices[lang] {
            print("[SpeechManager] Detected \(lang.rawValue), using \(voice)")
            return voice
        }
        return voiceModel
    }

    func speak(_ text: String) {
        guard let apiKey = KeychainManager.getAPIKey(), !apiKey.isEmpty else {
            print("[SpeechManager] No API key configured")
            return
        }

        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let model = resolveModel(for: trimmed)

        if trimmed.count < 1000 {
            speakViaREST(trimmed, apiKey: apiKey, model: model)
        } else {
            speakViaWebSocket(trimmed, apiKey: apiKey, model: model)
        }
    }

    // MARK: - REST path (short text)

    private func speakViaREST(_ text: String, apiKey: String, model: String) {
        isSpeaking = true
        restTask = Task { [weak self] in
            guard let url = URL(
                string: "https://api.deepgram.com/v1/speak?model=\(model)&encoding=linear16&sample_rate=48000&container=wav"
            ) else {
                await MainActor.run { self?.isSpeaking = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.httpBody = text.data(using: .utf8)
            request.timeoutInterval = 30

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    print("[SpeechManager] REST TTS HTTP error")
                    await MainActor.run { self?.isSpeaking = false }
                    return
                }
                await MainActor.run { self?.playWAVData(data) }
            } catch {
                if !Task.isCancelled {
                    print("[SpeechManager] REST TTS failed: \(error)")
                    await MainActor.run { self?.isSpeaking = false }
                }
            }
        }
    }

    private func playWAVData(_ data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            self.wavPlayer = player
            player.delegate = self._wavDelegate
            player.play()
        } catch {
            print("[SpeechManager] WAV playback failed: \(error)")
            isSpeaking = false
        }
    }

    // MARK: - WebSocket path (long text)

    private func speakViaWebSocket(_ text: String, apiKey: String, model: String) {
        let chunks = TextChunker.chunk(text)
        guard !chunks.isEmpty else { return }

        isSpeaking = true

        let client = DeepgramTTSClient()
        let player = AudioStreamPlayer()
        self.ttsClient = client
        self.audioPlayer = player

        let handler = TTSHandler(manager: self, player: player)
        client.delegate = handler
        self._handler = handler

        player.onPlaybackFinished = { [weak self] in
            Task { @MainActor in
                self?.finishPlayback()
            }
        }

        player.start()
        client.connect(apiKey: apiKey, model: model)

        Task.detached { [weak client] in
            guard let client else { return }
            for (index, chunk) in chunks.enumerated() {
                client.send(text: chunk)
                if (index + 1) % 3 == 0 || index == chunks.count - 1 {
                    client.flush()
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    func stop() {
        // REST path
        restTask?.cancel()
        restTask = nil
        wavPlayer?.stop()
        wavPlayer = nil

        // WebSocket path
        ttsClient?.clear()
        ttsClient?.close()
        ttsClient = nil
        audioPlayer?.stop()
        audioPlayer = nil

        isSpeaking = false
        isConnected = false
        _handler = nil
    }

    func testConnection(apiKey: String) async -> Bool {
        guard let url = URL(string: "https://api.deepgram.com/v1/auth/token") else {
            return false
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode == 200
            }
            return false
        } catch {
            print("[SpeechManager] Auth test failed: \(error)")
            return false
        }
    }

    private static let testQuotes = [
        "We are all connected in ways we don't always see. What we do for each other matters more than what we do for ourselves.",
        "The only true wisdom is in knowing you know nothing, and in that emptiness, finding room for wonder.",
        "In the middle of difficulty lies opportunity. Every obstacle is a doorway, if you have the courage to walk through it.",
        "We do not inherit the earth from our ancestors. We borrow it from our children, and we owe them a beautiful return.",
        "What matters most is how well you walk through the fire. Not the absence of flames, but the grace with which you move.",
        "Every person you meet is fighting a battle you know nothing about. Be kind. Always.",
        "The cosmos is within us. We are made of star stuff. We are a way for the universe to know itself.",
        "To live is the rarest thing in the world. Most people exist, that is all. But to truly live is to be awake to every moment.",
    ]

    /// Fetch TTS audio as WAV data for playback in the web view.
    func fetchTestAudio(apiKey: String? = nil, model: String? = nil) async -> Data? {
        let key = apiKey ?? KeychainManager.getAPIKey() ?? ""
        guard !key.isEmpty else { return nil }

        let quote = Self.testQuotes.randomElement()!
        let voiceID = model ?? voiceModel

        return await Task.detached {
            guard let url = URL(
                string: "https://api.deepgram.com/v1/speak?model=\(voiceID)&encoding=linear16&sample_rate=48000&container=wav"
            ) else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.httpBody = quote.data(using: .utf8)
            request.timeoutInterval = 15

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    print("[SpeechManager] Voice test HTTP error")
                    return nil
                }
                return data
            } catch {
                print("[SpeechManager] Voice test failed: \(error)")
                return nil
            }
        }.value
    }

    private func finishPlayback() {
        ttsClient?.close()
        ttsClient = nil
        audioPlayer = nil
        isSpeaking = false
        isConnected = false
        _handler = nil
    }

    func wavPlaybackFinished() {
        wavPlayer = nil
        isSpeaking = false
    }

    // Stored to prevent deallocation
    private var _handler: AnyObject?
    private lazy var _wavDelegate = WAVDelegate(manager: self)
}

// MARK: - WAV Playback Delegate

private final class WAVDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private weak var manager: SpeechManager?

    init(manager: SpeechManager) {
        self.manager = manager
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak manager] in
            manager?.wavPlaybackFinished()
        }
    }
}

// MARK: - TTS Delegate Handlers

private final class TTSHandler: DeepgramTTSDelegate, @unchecked Sendable {
    private weak var manager: SpeechManager?
    private let player: AudioStreamPlayer

    init(manager: SpeechManager, player: AudioStreamPlayer) {
        self.manager = manager
        self.player = player
    }

    func ttsClient(_ client: DeepgramTTSClient, didReceiveAudio data: Data) {
        player.enqueue(pcmData: data)
    }

    func ttsClient(_ client: DeepgramTTSClient, didReceiveControl message: [String: Any]) {
        if let type = message["type"] as? String {
            switch type {
            case "Warning":
                print("[DeepgramTTS] Warning: \(message["warn_msg"] ?? "unknown")")
            case "Metadata":
                break  // Connection metadata, log if needed
            default:
                break
            }
        }
    }

    func ttsClientDidClose(_ client: DeepgramTTSClient, error: Error?) {
        if let error {
            print("[DeepgramTTS] Connection closed with error: \(error)")
        }
        Task { @MainActor [weak manager] in
            manager?.isSpeaking = false
            manager?.isConnected = false
        }
    }
}

