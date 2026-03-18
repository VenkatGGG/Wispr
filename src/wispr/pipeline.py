from __future__ import annotations

from dataclasses import dataclass
import logging
import queue
import threading
import time

from wispr.audio import AudioRecorder, RecordedAudio
from wispr.formatter import OllamaFormatter
from wispr.output import TextInserter
from wispr.transcription import WhisperCppTranscriber


@dataclass(frozen=True)
class CaptureJob:
    audio: RecordedAudio
    created_at: float


class DictationPipeline:
    def __init__(
        self,
        recorder: AudioRecorder,
        transcriber: WhisperCppTranscriber,
        formatter: OllamaFormatter,
        inserter: TextInserter,
        minimum_capture_ms: int,
    ) -> None:
        self._recorder = recorder
        self._transcriber = transcriber
        self._formatter = formatter
        self._inserter = inserter
        self._minimum_capture_ms = minimum_capture_ms
        self._jobs: queue.Queue[CaptureJob | None] = queue.Queue()
        self._worker = threading.Thread(target=self._run_worker, name="wispr-pipeline", daemon=True)
        self._logger = logging.getLogger("wispr.pipeline")
        self._started = False

    def start(self) -> None:
        if self._started:
            return
        self._recorder.start()
        self._worker.start()
        self._started = True

    def stop(self) -> None:
        if not self._started:
            return

        self._jobs.put(None)
        self._worker.join(timeout=5)
        self._recorder.stop()
        self._transcriber.stop()
        self._formatter.stop()
        self._started = False

    def begin_capture(self) -> None:
        self._logger.debug("Starting capture.")
        self._recorder.begin_capture()

    def cancel_capture(self) -> None:
        self._logger.debug("Cancelling capture.")
        self._recorder.cancel_capture()

    def finish_capture(self, cancelled: bool) -> None:
        if cancelled:
            self._logger.debug("Capture cancelled before release.")
            self._recorder.cancel_capture()
            return

        recording = self._recorder.finish_capture(self._minimum_capture_ms)
        if recording is None:
            self._logger.debug("Skipping empty or short capture.")
            return

        self._logger.info("Queued capture (%sms).", recording.duration_ms)
        self._jobs.put(CaptureJob(audio=recording, created_at=time.monotonic()))

    def _run_worker(self) -> None:
        while True:
            job = self._jobs.get()
            if job is None:
                return

            try:
                transcription_started_at = time.monotonic()
                raw_transcript = self._transcriber.transcribe(job.audio.wav_bytes)
                transcription_ms = int((time.monotonic() - transcription_started_at) * 1000)

                formatting_started_at = time.monotonic()
                formatted_text = self._formatter.format_text(raw_transcript)
                formatting_ms = int((time.monotonic() - formatting_started_at) * 1000)

                if not formatted_text:
                    self._logger.info(
                        "Skipped insert: empty output. audio=%sms transcribe=%sms format=%sms",
                        job.audio.duration_ms,
                        transcription_ms,
                        formatting_ms,
                    )
                    continue

                insertion_started_at = time.monotonic()
                self._inserter.insert_text(formatted_text)
                insertion_ms = int((time.monotonic() - insertion_started_at) * 1000)

                self._logger.info(
                    "Inserted text. audio=%sms transcribe=%sms format=%sms insert=%sms",
                    job.audio.duration_ms,
                    transcription_ms,
                    formatting_ms,
                    insertion_ms,
                )
            except Exception:
                self._logger.exception("Dictation pipeline failed for a capture.")

