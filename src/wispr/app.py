from __future__ import annotations

import logging
import signal
import threading

from wispr.audio import AudioRecorder
from wispr.config import AppConfig
from wispr.formatter import OllamaFormatter
from wispr.hotkey import OptionHoldListener
from wispr.output import TextInserter
from wispr.pipeline import DictationPipeline
from wispr.transcription import WhisperCppTranscriber


class WisprApp:
    def __init__(self, config: AppConfig) -> None:
        recorder = AudioRecorder(config.audio)
        transcriber = WhisperCppTranscriber(config.whisper)
        formatter = OllamaFormatter(config.ollama, config.formatter)
        inserter = TextInserter(config.output)

        self._config = config
        self._logger = logging.getLogger("wispr.app")
        self._stop_event = threading.Event()
        self._formatter = formatter
        self._pipeline = DictationPipeline(
            recorder=recorder,
            transcriber=transcriber,
            formatter=formatter,
            inserter=inserter,
            minimum_capture_ms=config.minimum_capture_ms,
        )
        self._listener = OptionHoldListener(
            on_press=self._pipeline.begin_capture,
            on_release=self._pipeline.finish_capture,
            on_cancel=self._pipeline.cancel_capture,
            cancel_on_other_key=config.cancel_on_other_key,
            trigger_cooldown_ms=config.trigger_cooldown_ms,
        )

    def run(self) -> None:
        self._install_signal_handlers()
        self._logger.info("Starting Wispr.")
        self._warm_services()
        self._pipeline.start()
        try:
            self._listener.start()
        except Exception:
            self._pipeline.stop()
            raise

        try:
            self._stop_event.wait()
        finally:
            self.stop()

    def stop(self) -> None:
        if self._stop_event.is_set():
            return

        self._stop_event.set()
        self._listener.stop()
        self._pipeline.stop()
        self._logger.info("Stopped Wispr.")

    def _install_signal_handlers(self) -> None:
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGTERM, self._handle_signal)

    def _handle_signal(self, signum: int, frame: object) -> None:
        del signum, frame
        self.stop()

    def _warm_services(self) -> None:
        try:
            self._formatter.warmup()
        except Exception:
            self._logger.exception("Formatter warmup failed; first request may be slower.")
