# Clarion — macOS "Read Aloud" Service

## About
Menu bar app providing system-wide "Read Aloud" via NSServices, powered by Deepgram WebSocket streaming TTS.

## Build
```bash
make build    # swift build
make bundle   # .build/Clarion.app
make run      # build + open
make install  # /Applications + pbs flush
make clean    # rm build artifacts
```

## Architecture
- **ServiceProvider** — receives selected text via NSServices
- **SpeechManager** — orchestrates chunking → WebSocket → audio
- **DeepgramTTSClient** — WebSocket to `wss://api.deepgram.com/v1/speak`
- **AudioStreamPlayer** — AVAudioEngine streaming PCM playback
- **TextChunker** — sentence-boundary splitting (max 200 chars)
- **KeychainManager** — Deepgram API key stored in Keychain

## Conventions
- macOS 14+ / Swift 5.10
- SwiftUI for UI, AppKit integration for NSServices
- No third-party dependencies
- Conventional commits, no co-author lines
