# Wispr

This repo contains `Flow`, a local-first macOS dictation app, plus the older Python prototype it grew out of.

`Flow` runs as a menu bar app on macOS. Hold `Option`, speak, release, and it inserts the result into the focused text field without taking window focus.

## Current Default Behavior

- Native app name: `Flow`
- Platform: macOS only
- Trigger: bare `Option`
- Speech-to-text: `whisper.cpp`
- Default Whisper model: `models/ggml-small.en.bin`
- Text formatting: disabled by default in the native app
- Phrase replacements: enabled
- History: last 20 inserted entries

The current native default is Whisper-only output with single-line normalization. That means the app transcribes locally with `whisper.cpp`, flattens line breaks into spaces, applies phrase replacements, and inserts the final text.

If you want Ollama-based cleanup back, set `formatter.enabled = true` in [config.toml](/Users/sri/Desktop/silly_experiments/Wispr/config.toml).

## What Flow Does

1. Waits for a global `Option` key hold
2. Records microphone audio while the key is held
3. Sends the audio to a local `whisper.cpp` server
4. Optionally formats the transcript with Ollama when enabled
5. Applies phrase replacements from `phrases.json`
6. Inserts the result at the current cursor

## Native App

The native app is the main path now.

Key behavior:

- Single click the menu bar icon: show history
- Double click the menu bar icon: show phrases
- Right click the menu bar icon: show utility menu
- History entries are shown as a simple vertical list of final inserted text
- Clicking a history entry copies it to the clipboard
- Phrase matching is normalized for simple casing and punctuation variants

Important limitations:

- Works best in normal macOS text fields
- Some secure fields, games, VMs, or remote desktop apps may block insertion
- Accessibility and Input Monitoring permissions are required for reliable insertion

## Quick Start

### 1. Bootstrap Dependencies

Run:

```bash
make bootstrap
```

That installs the local dependencies used by the project, including `whisper.cpp`, Ollama, and the Python environment used by the prototype.

### 2. Build and Install the Native App

Run:

```bash
make native-build
make native-install
make native-open
```

Installed app location:

- [~/Applications/Flow.app](/Users/sri/Applications/Flow.app)

Build artifact location:

- [~/Library/Caches/Flow/Flow.app](/Users/sri/Library/Caches/Flow/Flow.app)

### 3. Grant macOS Permissions

Grant these to [~/Applications/Flow.app](/Users/sri/Applications/Flow.app):

- Accessibility
- Input Monitoring
- Microphone

### 4. Use It

1. Focus any text field
2. Hold `Option`
3. Speak
4. Release `Option`

## Login Startup

Install startup at login:

```bash
make native-login-install
```

Remove startup at login:

```bash
make native-login-uninstall
```

## Config

Main config file:

- [config.toml](/Users/sri/Desktop/silly_experiments/Wispr/config.toml)

Useful current knobs:

- `formatter.enabled = false`
  Native app uses Whisper-only output
- `formatter.enabled = true`
  Native app adds the Ollama rewrite step back in
- `prompt_path`
  Points at the formatter prompt file
- `restore_clipboard_delay_ms`
  Controls paste restore timing

Formatter prompt file:

- [prompts/formatter_system.txt](/Users/sri/Desktop/silly_experiments/Wispr/prompts/formatter_system.txt)

## Local Data Files

Application support directory:

- [~/Library/Application Support/Flow](/Users/sri/Library/Application%20Support/Flow)

Files:

- History: [~/Library/Application Support/Flow/history.json](/Users/sri/Library/Application%20Support/Flow/history.json)
- Phrases: [~/Library/Application Support/Flow/phrases.json](/Users/sri/Library/Application%20Support/Flow/phrases.json)
- Runtime config: [~/Library/Application Support/Flow/runtime.json](/Users/sri/Library/Application%20Support/Flow/runtime.json)

## Phrases

Phrase replacements are stored in `phrases.json`.

Example:

```json
[
  {
    "id": "D7F7B31E-9864-4D77-8E71-ED4A2DFE3B3D",
    "trigger": "LinkedIn",
    "replacement": "https://www.linkedin.com/"
  }
]
```

With that entry, speaking `LinkedIn` can resolve to the stored replacement instead of inserting the literal word.

## Python Prototype

The older Python daemon is still in the repo under [src/wispr](/Users/sri/Desktop/silly_experiments/Wispr/src/wispr), but the native app is the primary path now.

If you want to run the prototype anyway:

```bash
make doctor
make run
```

## Repo Layout

- Native app: [native/](/Users/sri/Desktop/silly_experiments/Wispr/native/Package.swift)
- Python prototype: [src/wispr](/Users/sri/Desktop/silly_experiments/Wispr/src/wispr)
- Scripts: [scripts/](/Users/sri/Desktop/silly_experiments/Wispr/scripts)
- Models: [models/](/Users/sri/Desktop/silly_experiments/Wispr/models)
