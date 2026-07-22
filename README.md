# Local Dictation

A strict-local macOS menu bar dictation app. Hold the configured shortcut, speak, release, and the app records audio, runs a local `whisper.cpp` CLI transcription, previews the result in an overlay, and pastes the text into the active app.

## Current MVP

- Native SwiftUI menu bar app.
- Global hold-to-record shortcut through KeyboardShortcuts.
- Local `whisper-cli` bridge; no cloud speech fallback.
- Floating non-activating overlay for listening/transcribing/result/error states.
- Clipboard paste insertion with clipboard restore.
- Settings for shortcut, `whisper-cli` path, model path, language, paste-on-release, and overlay visibility.
- `ContextProvider` boundary reserved for future active-app and visible-screen context.

## Requirements

- macOS 13 or later.
- Swift 6 toolchain.
- Local `whisper.cpp` build with `whisper-cli`.
- A local Whisper model file, for example `ggml-large-v3-turbo-q5_0.bin`.
- Microphone permission.
- Accessibility permission if paste-on-release is enabled.

## Build

```bash
swift build
```

For an app bundle:

```bash
scripts/build-app.sh
open LocalDictation.app
```

## Test

This machine's Command Line Tools installation does not expose `Testing` or `XCTest`, so automated core coverage is a Swift executable test runner:

```bash
swift run LocalDictationCoreTestRunner
```

## Default Settings

- Shortcut: Control-Space. (Note: macOS may map ⌃Space to "Select previous input source" if you have multiple input sources — rebind in Settings if it clashes.)
- `whisper-cli`: `/opt/homebrew/bin/whisper-cli`.
- Model: `~/models/ggml-large-v3-turbo-q5_0.bin`.
- Language: `auto`.
- Paste on release: enabled.
- Overlay: enabled.

## Notes

V1 intentionally does not include Gemma/local LLM post-processing or visible-screen context. Those should sit after transcription as a separate context/post-processing layer.
