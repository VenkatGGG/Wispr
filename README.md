# Wispr

Wispr is a local macOS dictation daemon that:

- starts recording when you hold either `Option` key,
- stops recording on release,
- transcribes with a persistent `whisper.cpp` server,
- cleans the transcript with a local Ollama model,
- pastes the final text into the currently focused app without stealing focus,
- exposes a floating history panel from the menu bar,
- supports a local phrase dictionary for exact-match replacements.

The implementation is intentionally narrow. There is no cloud dependency, no account system, and no settings UI.

## Stack

- Native path: Swift/AppKit menu bar app
- Python path: Python 3.11 daemon
- `whisper.cpp` server for a hot transcription model in RAM
- Ollama for local text cleanup
- Python prototype uses `sounddevice` and `PyObjC`

## Quick Start

The repo currently contains two runnable paths:

- the original Python daemon
- a native macOS menu bar app under [`native/`](/Users/sri/Desktop/silly_experiments/Wispr/native/Package.swift)

If you want the Wispr/Flow-style experience, use the native app.

### Python Daemon

1. Run `make bootstrap`
2. Grant these permissions when macOS prompts for them:
   - Accessibility
   - Input Monitoring
   - Microphone
3. Run `make doctor`
4. Run `make run`

### Native Menu Bar App

- Build the app bundle with `make native-build`
- Install the app into `~/Applications` with `make native-install`
- Open it with `make native-open`
- The build artifact is created at [`~/Library/Caches/WisprMenuBar/WisprMenuBar.app`](/Users/sri/Library/Caches/WisprMenuBar/WisprMenuBar.app)
- Install login startup with `make native-login-install`
- Remove login startup with `make native-login-uninstall`

For macOS permissions, grant access to the installed app at:

- `~/Applications/WisprMenuBar.app`

The native app keeps a rolling recent history of the last 20 entries at:

- `~/Library/Application Support/WisprMenuBar/history.json`

The native phrase dictionary lives at:

- `~/Library/Application Support/WisprMenuBar/phrases.json`

Example `phrases.json` entry:

```json
[
  {
    "id": "D7F7B31E-9864-4D77-8E71-ED4A2DFE3B3D",
    "trigger": "LinkedIn",
    "replacement": "https://www.linkedin.com/"
  }
]
```

## Behavior

- Recording starts only when `Option` is pressed by itself.
- If another key is pressed while `Option` is still held, the capture is cancelled.
- Very short taps are ignored.
- Left click on the menu bar icon opens the floating history panel.
- Right click on the menu bar icon opens the utility menu.
- Phrase replacements are exact-match only in the current version.
- Output is inserted via accessibility first, then falls back to paste and unicode typing.

## Config

Edit [`config.toml`](/Users/sri/Desktop/silly_experiments/Wispr/config.toml) to change ports, paths, model names, or timing knobs.

Edit [`prompts/formatter_system.txt`](/Users/sri/Desktop/silly_experiments/Wispr/prompts/formatter_system.txt) to change the rewrite prompt.

## Notes

- The bootstrap script downloads `ggml-small.en.bin` into [`models/`](/Users/sri/Desktop/silly_experiments/Wispr/models/.gitkeep).
- The default Ollama model is `qwen2.5:3b`.
- The app can start `ollama serve` and `whisper-server` itself when those binaries are installed locally.
