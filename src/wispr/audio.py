from __future__ import annotations

from dataclasses import dataclass
import io
import threading
import time
import wave

import numpy as np
import sounddevice as sd

from wispr.config import AudioConfig


@dataclass(frozen=True)
class RecordedAudio:
    wav_bytes: bytes
    duration_ms: int
    sample_rate_hz: int


class AudioRecorder:
    def __init__(self, config: AudioConfig) -> None:
        self._config = config
        self._lock = threading.Lock()
        self._chunks: list[np.ndarray] = []
        self._collecting = False
        self._capture_started_at: float | None = None
        self._stream: sd.InputStream | None = None

    def start(self) -> None:
        if self._stream is None:
            blocksize = max(1, int(self._config.sample_rate_hz * self._config.block_duration_ms / 1000))
            device = self._config.device or None
            self._stream = sd.InputStream(
                samplerate=self._config.sample_rate_hz,
                channels=self._config.channels,
                dtype="int16",
                blocksize=blocksize,
                device=device,
                latency="low",
                callback=self._on_audio,
            )

        if not self._stream.active:
            self._stream.start()

    def stop(self) -> None:
        if self._stream is None:
            return
        if self._stream.active:
            self._stream.stop()
        self._stream.close()
        self._stream = None

    def begin_capture(self) -> None:
        with self._lock:
            self._chunks = []
            self._collecting = True
            self._capture_started_at = time.monotonic()

    def cancel_capture(self) -> None:
        with self._lock:
            self._collecting = False
            self._chunks = []
            self._capture_started_at = None

    def finish_capture(self, minimum_capture_ms: int) -> RecordedAudio | None:
        with self._lock:
            chunks = list(self._chunks)
            capture_started_at = self._capture_started_at
            self._collecting = False
            self._chunks = []
            self._capture_started_at = None

        if not chunks or capture_started_at is None:
            return None

        audio = np.concatenate(chunks, axis=0).reshape(-1)
        duration_ms = int(len(audio) * 1000 / self._config.sample_rate_hz)
        if duration_ms < minimum_capture_ms:
            return None

        return RecordedAudio(
            wav_bytes=_encode_wav_bytes(audio, self._config.sample_rate_hz, self._config.channels),
            duration_ms=duration_ms,
            sample_rate_hz=self._config.sample_rate_hz,
        )

    def _on_audio(self, indata: np.ndarray, frames: int, time_info: object, status: sd.CallbackFlags) -> None:
        del frames, time_info
        if status:
            return

        with self._lock:
            if self._collecting:
                self._chunks.append(indata.copy())


def _encode_wav_bytes(audio: np.ndarray, sample_rate_hz: int, channels: int) -> bytes:
    with io.BytesIO() as buffer:
        with wave.open(buffer, "wb") as wav_file:
            wav_file.setnchannels(channels)
            wav_file.setsampwidth(2)
            wav_file.setframerate(sample_rate_hz)
            wav_file.writeframes(audio.astype(np.int16).tobytes())
        return buffer.getvalue()

