from __future__ import annotations

from dataclasses import dataclass
import logging
import time

import Quartz
from AppKit import NSPasteboard, NSPasteboardItem, NSPasteboardTypeString
from Foundation import NSData

from wispr.config import OutputConfig


ANSI_V_KEYCODE = 9


@dataclass(frozen=True)
class PasteboardItemSnapshot:
    data_by_type: dict[str, bytes]


@dataclass(frozen=True)
class ClipboardSnapshot:
    items: list[PasteboardItemSnapshot]


class TextInserter:
    def __init__(self, config: OutputConfig) -> None:
        self._config = config
        self._logger = logging.getLogger("wispr.output")

    def insert_text(self, text: str) -> None:
        if not text:
            return

        snapshot = self._capture_clipboard()
        try:
            self._write_text_to_clipboard(text)
            time.sleep(0.03)
            self._post_paste_shortcut()
            time.sleep(self._config.restore_clipboard_delay_ms / 1000)
        except Exception:
            self._logger.exception("Paste insertion failed; falling back to unicode typing.")
            self._type_text(text)
        finally:
            self._restore_clipboard(snapshot)

    def _capture_clipboard(self) -> ClipboardSnapshot:
        pasteboard = NSPasteboard.generalPasteboard()
        items = pasteboard.pasteboardItems() or []
        snapshots: list[PasteboardItemSnapshot] = []

        for item in items:
            data_by_type: dict[str, bytes] = {}
            for pasteboard_type in item.types() or []:
                data = item.dataForType_(pasteboard_type)
                if data is not None:
                    data_by_type[str(pasteboard_type)] = bytes(data)
            snapshots.append(PasteboardItemSnapshot(data_by_type=data_by_type))

        return ClipboardSnapshot(items=snapshots)

    def _restore_clipboard(self, snapshot: ClipboardSnapshot) -> None:
        pasteboard = NSPasteboard.generalPasteboard()
        pasteboard.clearContents()

        if not snapshot.items:
            return

        restored_items: list[NSPasteboardItem] = []
        for item_snapshot in snapshot.items:
            pasteboard_item = NSPasteboardItem.alloc().init()
            for pasteboard_type, raw_data in item_snapshot.data_by_type.items():
                ns_data = NSData.dataWithBytes_length_(raw_data, len(raw_data))
                pasteboard_item.setData_forType_(ns_data, pasteboard_type)
            restored_items.append(pasteboard_item)

        pasteboard.writeObjects_(restored_items)

    def _write_text_to_clipboard(self, text: str) -> None:
        pasteboard = NSPasteboard.generalPasteboard()
        pasteboard.clearContents()
        pasteboard.setString_forType_(text, NSPasteboardTypeString)

    def _post_paste_shortcut(self) -> None:
        key_down = Quartz.CGEventCreateKeyboardEvent(None, ANSI_V_KEYCODE, True)
        Quartz.CGEventSetFlags(key_down, Quartz.kCGEventFlagMaskCommand)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_down)

        key_up = Quartz.CGEventCreateKeyboardEvent(None, ANSI_V_KEYCODE, False)
        Quartz.CGEventSetFlags(key_up, Quartz.kCGEventFlagMaskCommand)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_up)

    def _type_text(self, text: str) -> None:
        for character in text:
            key_down = Quartz.CGEventCreateKeyboardEvent(None, 0, True)
            Quartz.CGEventKeyboardSetUnicodeString(key_down, len(character), character)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_down)

            key_up = Quartz.CGEventCreateKeyboardEvent(None, 0, False)
            Quartz.CGEventKeyboardSetUnicodeString(key_up, len(character), character)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_up)
