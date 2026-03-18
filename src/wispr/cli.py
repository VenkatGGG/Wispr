from __future__ import annotations

import argparse
import logging
from pathlib import Path
import sys

import Quartz

from wispr.app import WisprApp
from wispr.config import AppConfig
from wispr.logging_utils import configure_logging
from wispr.services import is_tcp_port_open, resolve_command


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Local macOS dictation daemon.")
    parser.add_argument("--config", default="config.toml", help="Path to the config TOML file.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("run", help="Run the dictation daemon.")
    subparsers.add_parser("doctor", help="Check local dependencies and config.")

    args = parser.parse_args(argv)
    config = AppConfig.load(Path(args.config))
    configure_logging(config.log_level)

    if args.command == "doctor":
        return run_doctor(config)
    if args.command == "run":
        WisprApp(config).run()
        return 0

    parser.error(f"Unknown command: {args.command}")
    return 2


def run_doctor(config: AppConfig) -> int:
    logger = logging.getLogger("wispr.doctor")
    ok = True
    whisper_binary_ok = False
    ollama_binary_ok = False

    def check(label: str, passed: bool, detail: str) -> None:
        nonlocal ok
        status = "OK" if passed else "FAIL"
        print(f"{status:4} {label}: {detail}")
        if not passed:
            ok = False

    check("config", config.config_path.exists(), str(config.config_path))
    check("prompt", config.formatter.prompt_path.exists(), str(config.formatter.prompt_path))
    check("whisper model", config.whisper.model_path.exists(), str(config.whisper.model_path))

    try:
        whisper_command = resolve_command(config.whisper.command, ["whisper-whisper-server", "whisper-server"])[0]
        whisper_binary_ok = True
        check("whisper binary", True, whisper_command)
    except FileNotFoundError as exc:
        check("whisper binary", False, str(exc))

    try:
        ollama_command = resolve_command(config.ollama.command, ["ollama"])[0]
        ollama_binary_ok = True
        check("ollama binary", True, ollama_command)
    except FileNotFoundError as exc:
        check("ollama binary", False, str(exc))

    whisper_port_open = is_tcp_port_open(config.whisper.host, config.whisper.port)
    ollama_port_open = is_tcp_port_open(config.ollama.host, config.ollama.port)

    check(
        "whisper port",
        whisper_port_open or (config.whisper.auto_start and whisper_binary_ok),
        f"{config.whisper.host}:{config.whisper.port} "
        f"(open={whisper_port_open}, auto_start={config.whisper.auto_start})",
    )
    check(
        "ollama port",
        ollama_port_open or (config.ollama.auto_start and ollama_binary_ok),
        f"{config.ollama.host}:{config.ollama.port} "
        f"(open={ollama_port_open}, auto_start={config.ollama.auto_start})",
    )
    check(
        "listen access",
        bool(Quartz.CGPreflightListenEventAccess()),
        "Grant Input Monitoring / Accessibility if false.",
    )
    check(
        "post access",
        bool(Quartz.CGPreflightPostEventAccess()),
        "Grant Accessibility if false.",
    )

    try:
        import sounddevice as sd

        devices = sd.query_devices()
        check("audio input", bool(devices), "Sound devices are visible.")
    except Exception as exc:
        check("audio input", False, str(exc))

    if not ok:
        logger.warning("Doctor found problems.")
        return 1

    print("Doctor checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
