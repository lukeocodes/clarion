import AVFoundation
import Foundation

final class AudioStreamPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var scheduledBufferCount = 0
    private var completedBufferCount = 0
    private let lock = NSLock()
    var onPlaybackFinished: (() -> Void)?

    private(set) var isPlaying = false

    init() {
        // Deepgram linear16: signed 16-bit integer PCM, 48 kHz, mono
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000,
            channels: 1,
            interleaved: true
        )!
    }

    func start() {
        guard !isPlaying else { return }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playerNode.play()
            isPlaying = true
        } catch {
            print("[AudioStreamPlayer] Failed to start engine: \(error)")
        }
    }

    func enqueue(pcmData: Data) {
        guard isPlaying, !pcmData.isEmpty else { return }

        let frameCount = UInt32(pcmData.count / MemoryLayout<Int16>.size)
        guard frameCount > 0 else { return }

        // Convert Int16 PCM data to Float32 PCM buffer for AVAudioPlayerNode
        guard
            let floatFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48000,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCount)
        else { return }

        buffer.frameLength = frameCount

        pcmData.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            guard let floatChannelData = buffer.floatChannelData else { return }

            let floatPtr = floatChannelData[0]
            for i in 0..<Int(frameCount) {
                floatPtr[i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        lock.lock()
        scheduledBufferCount += 1
        lock.unlock()

        playerNode.scheduleBuffer(buffer) { [weak self] in
            self?.bufferCompleted()
        }
    }

    private func bufferCompleted() {
        lock.lock()
        completedBufferCount += 1
        let allDone = completedBufferCount >= scheduledBufferCount
        lock.unlock()

        if allDone {
            DispatchQueue.main.async { [weak self] in
                self?.onPlaybackFinished?()
            }
        }
    }

    func stop() {
        guard isPlaying else { return }

        playerNode.stop()
        engine.stop()
        engine.detach(playerNode)
        isPlaying = false

        lock.lock()
        scheduledBufferCount = 0
        completedBufferCount = 0
        lock.unlock()
    }
}
