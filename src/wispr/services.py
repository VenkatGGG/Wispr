from __future__ import annotations

import logging
import shlex
import shutil
import socket
import subprocess
import time
from typing import Callable


class ManagedSubprocess:
    def __init__(
        self,
        name: str,
        argv: list[str],
        healthcheck: Callable[[], bool],
        startup_timeout_seconds: float,
    ) -> None:
        self._name = name
        self._argv = argv
        self._healthcheck = healthcheck
        self._startup_timeout_seconds = startup_timeout_seconds
        self._logger = logging.getLogger(f"wispr.service.{name}")
        self._process: subprocess.Popen[bytes] | None = None

    def ensure_running(self) -> None:
        if self._healthcheck():
            return

        if self._process is None or self._process.poll() is not None:
            self._logger.info("Starting %s: %s", self._name, " ".join(self._argv))
            self._process = subprocess.Popen(
                self._argv,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        deadline = time.monotonic() + self._startup_timeout_seconds
        while time.monotonic() < deadline:
            if self._healthcheck():
                return
            if self._process.poll() is not None:
                raise RuntimeError(f"{self._name} exited before it became ready.")
            time.sleep(0.25)

        raise TimeoutError(f"{self._name} did not become ready within {self._startup_timeout_seconds} seconds.")

    def stop(self) -> None:
        if self._process is None or self._process.poll() is not None:
            return
        self._logger.info("Stopping %s", self._name)
        self._process.terminate()
        try:
            self._process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self._process.kill()


def resolve_command(explicit_command: str, candidates: list[str]) -> list[str]:
    if explicit_command.strip():
        argv = shlex.split(explicit_command)
        executable = shutil.which(argv[0]) or argv[0]
        return [executable, *argv[1:]]

    for candidate in candidates:
        executable = shutil.which(candidate)
        if executable:
            return [executable]

    joined = ", ".join(candidates)
    raise FileNotFoundError(f"Could not find any of these commands: {joined}")


def is_tcp_port_open(host: str, port: int, timeout_seconds: float = 0.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout_seconds):
            return True
    except OSError:
        return False

