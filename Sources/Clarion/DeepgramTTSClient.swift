import Foundation

protocol DeepgramTTSDelegate: AnyObject {
    func ttsClient(_ client: DeepgramTTSClient, didReceiveAudio data: Data)
    func ttsClient(_ client: DeepgramTTSClient, didReceiveControl message: [String: Any])
    func ttsClientDidClose(_ client: DeepgramTTSClient, error: Error?)
}

final class DeepgramTTSClient: NSObject, URLSessionWebSocketDelegate {
    weak var delegate: DeepgramTTSDelegate?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var charsSinceFlush = 0

    // Deepgram limits: 2000 chars/message, stay under 1000 before flushing
    private let flushThreshold = 900

    private(set) var isConnected = false

    func connect(apiKey: String, model: String = "aura-2-thalia-en") {
        let urlString =
            "wss://api.deepgram.com/v1/speak?encoding=linear16&sample_rate=48000&model=\(model)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session?.webSocketTask(with: request)
        task?.resume()

        isConnected = true
        receiveLoop()
    }

    func send(text: String) {
        guard isConnected else { return }

        // Auto-flush if approaching buffer limit
        if charsSinceFlush + text.count > flushThreshold {
            flush()
        }

        let message: [String: String] = ["type": "Speak", "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let string = String(data: data, encoding: .utf8)!

        task?.send(.string(string)) { [weak self] error in
            if let error {
                print("[DeepgramTTS] Send error: \(error)")
                self?.disconnect(error: error)
            }
        }

        charsSinceFlush += text.count
    }

    func flush() {
        guard isConnected else { return }

        let message = #"{"type":"Flush"}"#
        task?.send(.string(message)) { [weak self] error in
            if let error {
                print("[DeepgramTTS] Flush error: \(error)")
                self?.disconnect(error: error)
            }
        }
        charsSinceFlush = 0
    }

    func clear() {
        guard isConnected else { return }

        let message = #"{"type":"Clear"}"#
        task?.send(.string(message)) { _ in }
        charsSinceFlush = 0
    }

    func close() {
        guard isConnected else { return }

        let message = #"{"type":"Close"}"#
        task?.send(.string(message)) { [weak self] _ in
            self?.task?.cancel(with: .normalClosure, reason: nil)
        }
        isConnected = false
        charsSinceFlush = 0
    }

    func disconnect(error: Error? = nil) {
        task?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
        charsSinceFlush = 0
        delegate?.ttsClientDidClose(self, error: error)
    }

    // MARK: - Receive loop

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self, self.isConnected else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.delegate?.ttsClient(self, didReceiveAudio: data)
                case .string(let text):
                    if let jsonData = text.data(using: .utf8),
                        let json = try? JSONSerialization.jsonObject(with: jsonData)
                            as? [String: Any]
                    {
                        self.delegate?.ttsClient(self, didReceiveControl: json)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()

            case .failure(let error):
                self.disconnect(error: error)
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
    ) {
        isConnected = false
        delegate?.ttsClientDidClose(self, error: nil)
    }
}
