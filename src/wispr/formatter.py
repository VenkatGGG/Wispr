from __future__ import annotations

import json
import logging
import subprocess
import urllib.request

from wispr.config import FormatterConfig, OllamaConfig
from wispr.services import ManagedSubprocess, is_tcp_port_open, resolve_command


class PromptTemplate:
    def __init__(self, config: FormatterConfig) -> None:
        self._path = config.prompt_path
        self._max_input_chars = config.max_input_chars
        self._instructions = self._path.read_text(encoding="utf-8").strip()

    def render(self, raw_transcript: str) -> str:
        transcript = raw_transcript.strip()[: self._max_input_chars]
        return (
            f"{self._instructions}\n\n"
            "Raw transcript:\n"
            "<<<\n"
            f"{transcript}\n"
            ">>>\n\n"
            "Corrected text:"
        )


class OllamaFormatter:
    def __init__(self, ollama_config: OllamaConfig, formatter_config: FormatterConfig) -> None:
        self._ollama_config = ollama_config
        self._prompt_template = PromptTemplate(formatter_config)
        self._logger = logging.getLogger("wispr.formatter")
        self._managed_process: ManagedSubprocess | None = None
        self._model_ready = False

    def format_text(self, raw_transcript: str) -> str:
        transcript = raw_transcript.strip()
        if not transcript:
            return ""

        self._ensure_ready()
        self._ensure_model_available()

        request_body = json.dumps(
            {
                "model": self._ollama_config.model,
                "prompt": self._prompt_template.render(transcript),
                "stream": False,
                "options": {
                    "temperature": 0,
                },
            }
        ).encode()
        request = urllib.request.Request(
            url=f"http://{self._ollama_config.host}:{self._ollama_config.port}/api/generate",
            data=request_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=self._ollama_config.request_timeout_seconds) as response:
            payload = json.loads(response.read().decode())

        formatted = payload.get("response", "")
        if not isinstance(formatted, str):
            raise ValueError("Unexpected Ollama response format.")
        return formatted.strip()

    def warmup(self) -> None:
        self._ensure_ready()
        self._ensure_model_available()
        request_body = json.dumps(
            {
                "model": self._ollama_config.model,
                "prompt": "",
                "stream": False,
                "keep_alive": "15m",
                "options": {
                    "temperature": 0,
                },
            }
        ).encode()
        request = urllib.request.Request(
            url=f"http://{self._ollama_config.host}:{self._ollama_config.port}/api/generate",
            data=request_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=self._ollama_config.request_timeout_seconds):
            return

    def stop(self) -> None:
        if self._managed_process is not None:
            self._managed_process.stop()

    def _ensure_ready(self) -> None:
        if is_tcp_port_open(self._ollama_config.host, self._ollama_config.port):
            return
        if not self._ollama_config.auto_start:
            raise RuntimeError("Ollama is not reachable and auto_start is disabled.")

        if self._managed_process is None:
            command = resolve_command(self._ollama_config.command, ["ollama"])
            argv = [*command, "serve"]
            self._managed_process = ManagedSubprocess(
                name="ollama",
                argv=argv,
                healthcheck=lambda: is_tcp_port_open(self._ollama_config.host, self._ollama_config.port),
                startup_timeout_seconds=20,
            )

        self._managed_process.ensure_running()

    def _ensure_model_available(self) -> None:
        if self._model_ready:
            return

        available_models = self._list_models()
        if _model_present(available_models, self._ollama_config.model):
            self._model_ready = True
            return

        if not self._ollama_config.auto_pull_model:
            raise RuntimeError(
                f"Ollama model {self._ollama_config.model!r} is not installed. "
                "Run the bootstrap script or set auto_pull_model=true."
            )

        command = resolve_command(self._ollama_config.command, ["ollama"])
        subprocess.run([*command, "pull", self._ollama_config.model], check=True)
        self._model_ready = True

    def _list_models(self) -> set[str]:
        request = urllib.request.Request(
            url=f"http://{self._ollama_config.host}:{self._ollama_config.port}/api/tags",
            method="GET",
        )
        with urllib.request.urlopen(request, timeout=self._ollama_config.request_timeout_seconds) as response:
            payload = json.loads(response.read().decode())

        models = payload.get("models", [])
        results: set[str] = set()
        if isinstance(models, list):
            for item in models:
                if isinstance(item, dict):
                    name = item.get("name")
                    if isinstance(name, str):
                        results.add(name)
        return results


def _model_present(models: set[str], wanted_model: str) -> bool:
    if wanted_model in models:
        return True
    return f"{wanted_model}:latest" in models
