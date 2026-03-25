# Wispr

`Flow` is a local-first macOS dictation app in this repo.

Hold `Option`, speak, release, and your words are inserted into the text field you are currently using.

## What It Does

- runs as a lightweight menu bar app
- records while you hold `Option`
- transcribes speech locally with `whisper.cpp`
- optionally cleans up text with a local Ollama model
- inserts the result at your cursor
- keeps a small local history
- supports custom phrase replacements

Everything stays on your machine.

## Current Default

The native app currently uses:

- `whisper.cpp` for transcription
- `ggml-small.en.bin` as the default Whisper model
- phrase replacements
- single-line insertion

Ollama-based cleanup is currently turned off by default.

If you want to turn it back on, set `formatter.enabled = true` in [config.toml](config.toml).

## Quick Start

### 1. Install Dependencies

```bash
make bootstrap
```

### 2. Build and Install Flow

```bash
make native-build
make native-install
make native-open
```

The installed app lives at:

- `~/Applications/Flow.app`

### 3. Grant macOS Permissions

Grant these permissions to `Flow.app`:

- Accessibility
- Input Monitoring
- Microphone

### 4. Start Dictating

1. Focus any text field
2. Hold `Option`
3. Speak
4. Release `Option`

## How To Use It

- single click the menu bar icon to open history
- double click the menu bar icon to open phrases
- right click the menu bar icon for the utility menu

## Phrases

You can create personal replacements such as:

- `LinkedIn` -> `https://www.linkedin.com/`

Phrases are stored locally in:

- `~/Library/Application Support/Flow/phrases.json`

## History

Flow keeps the last 20 entries locally in:

- `~/Library/Application Support/Flow/history.json`

## Config

Main config:

- [config.toml](config.toml)

Rewrite prompt:

- [prompts/formatter_system.txt](prompts/formatter_system.txt)

Useful settings:

- `formatter.enabled`
- `restore_clipboard_delay_ms`

## Start At Login

Install login startup:

```bash
make native-login-install
```

Remove login startup:

```bash
make native-login-uninstall
```

## Troubleshooting

If text is not being inserted:

- make sure `Flow.app` has Accessibility access
- make sure `Flow.app` has Input Monitoring access
- test in TextEdit first

If microphone input is not working:

- make sure `Flow.app` has Microphone access
- check the active input device in macOS Sound settings

## Repo Layout

- native app: [native/](native/)
- python prototype: [src/wispr](src/wispr)
- scripts: [scripts/](scripts/)
- models: [models/](models/)

## Notes

The Python prototype is still in the repo, but the native app is the main path now.
