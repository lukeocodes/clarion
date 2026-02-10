# Clarion

A macOS menu bar app that reads text aloud using [Deepgram's](https://deepgram.com) Aura 2 text-to-speech API. Zero dependencies — built entirely on macOS system frameworks.

## Features

- **Right-click → Read Aloud** — Select text in any app, right-click, and choose "Read Aloud" from the Services menu. Works in Safari, Notes, VS Code, and anywhere else that supports macOS Services.
- **Automatic language detection** — Detects the language of selected text and switches to an appropriate Deepgram voice. Supports English, French, Spanish, German, Italian, Dutch, and Japanese out of the box.

## Install

Download the DMG from the [latest release](https://github.com/lukeocodes/clarion/releases), or build from source:

```
make install
```

## Requirements

- macOS 14+
- A [Deepgram API key](https://console.deepgram.com) (free tier available)
