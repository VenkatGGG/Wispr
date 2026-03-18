from __future__ import annotations

import logging
import threading
import time
from typing import Callable

import Quartz


CONFLICTING_MODIFIER_MASK = (
    Quartz.kCGEventFlagMaskCommand
    | Quartz.kCGEventFlagMaskControl
    | Quartz.kCGEventFlagMaskShift
)


class OptionHoldListener:
    def __init__(
        self,
        on_press: Callable[[], None],
        on_release: Callable[[bool], None],
        on_cancel: Callable[[], None],
        cancel_on_other_key: bool,
        trigger_cooldown_ms: int,
    ) -> None:
        self._on_press = on_press
        self._on_release = on_release
        self._on_cancel = on_cancel
        self._cancel_on_other_key = cancel_on_other_key
        self._cooldown_seconds = trigger_cooldown_ms / 1000
        self._logger = logging.getLogger("wispr.hotkey")
        self._thread: threading.Thread | None = None
        self._ready = threading.Event()
        self._run_loop = None
        self._tap = None
        self._option_down = False
        self._capture_cancelled = False
        self._last_release_at = 0.0
        self._startup_error: Exception | None = None

    def start(self) -> None:
        if self._thread is not None:
            return

        self._thread = threading.Thread(target=self._run, name="wispr-option-listener", daemon=True)
        self._thread.start()
        if not self._ready.wait(timeout=5):
            raise TimeoutError("Timed out while starting the hotkey listener.")

        if self._startup_error is not None:
            raise self._startup_error

    def stop(self) -> None:
        if self._run_loop is not None:
            Quartz.CFRunLoopStop(self._run_loop)
        if self._thread is not None:
            self._thread.join(timeout=2)
        self._thread = None

    def _run(self) -> None:
        try:
            mask = (1 << Quartz.kCGEventFlagsChanged) | (1 << Quartz.kCGEventKeyDown)
            self._tap = Quartz.CGEventTapCreate(
                Quartz.kCGHIDEventTap,
                Quartz.kCGHeadInsertEventTap,
                Quartz.kCGEventTapOptionListenOnly,
                mask,
                self._callback,
                None,
            )
            if self._tap is None:
                raise PermissionError(
                    "Could not create a global event tap. Grant Accessibility and Input Monitoring permissions."
                )

            run_loop_source = Quartz.CFMachPortCreateRunLoopSource(None, self._tap, 0)
            self._run_loop = Quartz.CFRunLoopGetCurrent()
            Quartz.CFRunLoopAddSource(self._run_loop, run_loop_source, Quartz.kCFRunLoopCommonModes)
            Quartz.CGEventTapEnable(self._tap, True)
        except Exception as exc:
            self._startup_error = exc
            self._ready.set()
            return

        self._ready.set()
        Quartz.CFRunLoopRun()

    def _callback(self, proxy: object, event_type: int, event: object, refcon: object) -> object:
        del proxy, refcon
        try:
            if event_type in (Quartz.kCGEventTapDisabledByTimeout, Quartz.kCGEventTapDisabledByUserInput):
                if self._tap is not None:
                    Quartz.CGEventTapEnable(self._tap, True)
                return event

            if event_type == Quartz.kCGEventFlagsChanged:
                self._handle_flags_changed(Quartz.CGEventGetFlags(event))
            elif event_type == Quartz.kCGEventKeyDown:
                self._handle_key_down()
        except Exception:
            self._logger.exception("Hotkey listener callback failed.")

        return event

    def _handle_flags_changed(self, flags: int) -> None:
        option_down = bool(flags & Quartz.kCGEventFlagMaskAlternate)
        conflicting_modifiers = bool(flags & CONFLICTING_MODIFIER_MASK)

        if option_down and not self._option_down:
            now = time.monotonic()
            if conflicting_modifiers or now - self._last_release_at < self._cooldown_seconds:
                return
            self._option_down = True
            self._capture_cancelled = False
            self._on_press()
            return

        if not option_down and self._option_down:
            self._option_down = False
            self._last_release_at = time.monotonic()
            cancelled = self._capture_cancelled
            self._capture_cancelled = False
            self._on_release(cancelled)
            return

        if option_down and self._option_down and conflicting_modifiers and not self._capture_cancelled:
            self._capture_cancelled = True
            self._on_cancel()

    def _handle_key_down(self) -> None:
        if self._option_down and self._cancel_on_other_key and not self._capture_cancelled:
            self._capture_cancelled = True
            self._on_cancel()
