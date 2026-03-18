from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import tomllib


DEFAULT_CONFIG_NAME = "config.toml"


@dataclass(frozen=True)
class AudioConfig:
    sample_rate_hz: int
    channels: int
    block_duration_ms: int
    device: str


@dataclass(frozen=True)
class WhisperConfig:
    host: str
    port: int
    model_path: Path
    language: str
    endpoint: str
    command: str
    auto_start: bool
    startup_timeout_seconds: float


@dataclass(frozen=True)
class OllamaConfig:
    host: str
    port: int
    model: str
    command: str
    auto_start: bool
    auto_pull_model: bool
    request_timeout_seconds: float


@dataclass(frozen=True)
class FormatterConfig:
    prompt_path: Path
    max_input_chars: int


@dataclass(frozen=True)
class OutputConfig:
    restore_clipboard_delay_ms: int


@dataclass(frozen=True)
class AppConfig:
    root_dir: Path
    config_path: Path
    log_level: str
    cancel_on_other_key: bool
    minimum_capture_ms: int
    trigger_cooldown_ms: int
    audio: AudioConfig
    whisper: WhisperConfig
    ollama: OllamaConfig
    formatter: FormatterConfig
    output: OutputConfig

    @classmethod
    def load(cls, config_path: str | Path | None = None) -> "AppConfig":
        root_dir = Path.cwd().resolve()
        resolved_config_path = (
            Path(config_path).expanduser().resolve()
            if config_path is not None
            else (root_dir / DEFAULT_CONFIG_NAME).resolve()
        )

        data: dict[str, object] = {}
        if resolved_config_path.exists():
            with resolved_config_path.open("rb") as handle:
                data = tomllib.load(handle)

        base_dir = resolved_config_path.parent if resolved_config_path.exists() else root_dir
        audio = data.get("audio", {})
        whisper = data.get("whisper", {})
        ollama = data.get("ollama", {})
        formatter = data.get("formatter", {})
        output = data.get("output", {})

        return cls(
            root_dir=root_dir,
            config_path=resolved_config_path,
            log_level=str(data.get("log_level", "INFO")),
            cancel_on_other_key=bool(data.get("cancel_on_other_key", True)),
            minimum_capture_ms=int(data.get("minimum_capture_ms", 180)),
            trigger_cooldown_ms=int(data.get("trigger_cooldown_ms", 120)),
            audio=AudioConfig(
                sample_rate_hz=int(_get(audio, "sample_rate_hz", 16000)),
                channels=int(_get(audio, "channels", 1)),
                block_duration_ms=int(_get(audio, "block_duration_ms", 50)),
                device=str(_get(audio, "device", "")),
            ),
            whisper=WhisperConfig(
                host=str(_get(whisper, "host", "127.0.0.1")),
                port=int(_get(whisper, "port", 8178)),
                model_path=_resolve_path(base_dir, str(_get(whisper, "model_path", "models/ggml-base.en.bin"))),
                language=str(_get(whisper, "language", "en")),
                endpoint=str(_get(whisper, "endpoint", "")),
                command=str(_get(whisper, "command", "")),
                auto_start=bool(_get(whisper, "auto_start", True)),
                startup_timeout_seconds=float(_get(whisper, "startup_timeout_seconds", 20)),
            ),
            ollama=OllamaConfig(
                host=str(_get(ollama, "host", "127.0.0.1")),
                port=int(_get(ollama, "port", 11434)),
                model=str(_get(ollama, "model", "phi3:mini")),
                command=str(_get(ollama, "command", "")),
                auto_start=bool(_get(ollama, "auto_start", True)),
                auto_pull_model=bool(_get(ollama, "auto_pull_model", False)),
                request_timeout_seconds=float(_get(ollama, "request_timeout_seconds", 20)),
            ),
            formatter=FormatterConfig(
                prompt_path=_resolve_path(base_dir, str(_get(formatter, "prompt_path", "prompts/formatter_system.txt"))),
                max_input_chars=int(_get(formatter, "max_input_chars", 4000)),
            ),
            output=OutputConfig(
                restore_clipboard_delay_ms=int(_get(output, "restore_clipboard_delay_ms", 120)),
            ),
        )


def _get(data: object, key: str, default: object) -> object:
    if isinstance(data, dict):
        return data.get(key, default)
    return default


def _resolve_path(base_dir: Path, raw_path: str) -> Path:
    path = Path(raw_path).expanduser()
    if not path.is_absolute():
        path = (base_dir / path).resolve()
    return path

