from __future__ import annotations

import json
import logging
from pathlib import Path
import urllib.error
import urllib.request

from wispr.config import WhisperConfig
from wispr.http_utils import build_multipart_form_data, decode_json_or_text
from wispr.services import ManagedSubprocess, is_tcp_port_open, resolve_command


class WhisperCppTranscriber:
    def __init__(self, config: WhisperConfig) -> None:
        self._config = config
        self._logger = logging.getLogger("wispr.transcription")
        self._managed_process: ManagedSubprocess | None = None
        self._resolved_endpoint: tuple[str, dict[str, str]] | None = None

    def transcribe(self, wav_bytes: bytes) -> str:
        self._ensure_ready()
        endpoint_attempts = (
            [self._resolved_endpoint]
            if self._resolved_endpoint is not None
            else self._endpoint_attempts()
        )
        errors: list[str] = []

        for endpoint, fields in endpoint_attempts:
            try:
                response_body = self._post_audio(endpoint, fields, wav_bytes)
                if self._resolved_endpoint is None:
                    self._resolved_endpoint = (endpoint, fields)
                return self._extract_text(response_body).strip()
            except Exception as exc:
                errors.append(f"{endpoint}: {exc}")

        raise RuntimeError("Whisper transcription failed. " + " | ".join(errors))

    def stop(self) -> None:
        if self._managed_process is not None:
            self._managed_process.stop()

    def _ensure_ready(self) -> None:
        if is_tcp_port_open(self._config.host, self._config.port):
            return
        if not self._config.auto_start:
            raise RuntimeError("Whisper server is not reachable and auto_start is disabled.")
        if not self._config.model_path.exists():
            raise FileNotFoundError(f"Whisper model file not found at {self._config.model_path}")

        if self._managed_process is None:
            command = resolve_command(self._config.command, ["whisper-whisper-server", "whisper-server"])
            argv = [
                *command,
                "--host",
                self._config.host,
                "--port",
                str(self._config.port),
                "-m",
                str(self._config.model_path),
            ]
            self._managed_process = ManagedSubprocess(
                name="whisper.cpp",
                argv=argv,
                healthcheck=lambda: is_tcp_port_open(self._config.host, self._config.port),
                startup_timeout_seconds=self._config.startup_timeout_seconds,
            )

        self._managed_process.ensure_running()

    def _endpoint_attempts(self) -> list[tuple[str, dict[str, str]]]:
        if self._config.endpoint:
            return [(self._config.endpoint, {"language": self._config.language})]

        return [
            (
                "/v1/audio/transcriptions",
                {
                    "language": self._config.language,
                    "model": "whisper-1",
                    "response_format": "json",
                },
            ),
            ("/inference", {"language": self._config.language}),
            ("/inference", {}),
        ]

    def _post_audio(self, endpoint: str, fields: dict[str, str], wav_bytes: bytes) -> bytes:
        url = f"http://{self._config.host}:{self._config.port}{endpoint}"
        body, content_type = build_multipart_form_data(
            fields=fields,
            file_field_name="file",
            filename="dictation.wav",
            file_bytes=wav_bytes,
            content_type="audio/wav",
        )

        request = urllib.request.Request(
            url=url,
            data=body,
            headers={"Content-Type": content_type},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=max(self._config.startup_timeout_seconds, 10)) as response:
            return response.read()

    def _extract_text(self, payload: bytes) -> str:
        decoded = decode_json_or_text(payload)
        if isinstance(decoded, str):
            return decoded

        if isinstance(decoded, dict):
            for key in ("text", "response", "output"):
                value = decoded.get(key)
                if isinstance(value, str):
                    return value

            segments = decoded.get("segments")
            if isinstance(segments, list):
                pieces = [
                    segment.get("text", "")
                    for segment in segments
                    if isinstance(segment, dict) and isinstance(segment.get("text"), str)
                ]
                return "".join(pieces)

        raise ValueError(f"Unexpected whisper response: {json.dumps(decoded)[:200]}")
