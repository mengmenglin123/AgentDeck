"""Safe process lifecycle seam for a production HuanHermes Host adapter.

This module intentionally does not know how Claude Code, Codex, or Hermes
format prompts. The Bridge/Mgmt adapter owns that translation; this module
only owns argv validation, process groups, stdin/stdout, cancellation, and
cleanup.
"""

from __future__ import annotations

import os
import selectors
import signal
import subprocess
from dataclasses import dataclass
from typing import Callable, Mapping, Protocol, runtime_checkable


class AdapterError(RuntimeError):
    """Raised for invalid adapter configuration or process state."""


@dataclass(frozen=True)
class AgentSpec:
    """Executable definition supplied by a trusted Host configuration."""

    agent_type: str
    command: tuple[str, ...]
    capabilities: tuple[str, ...] = (
        "stream",
        "cancel",
        "terminal",
    )
    environment: Mapping[str, str] | None = None
    close_stdin_after_send: bool = False

    def __post_init__(self) -> None:
        if not self.agent_type.strip():
            raise ValueError("agent_type must not be empty")
        if not self.command or any(not part for part in self.command):
            raise ValueError("command must be a non-empty argv tuple")
        if any("\x00" in part for part in self.command):
            raise ValueError("command must not contain NUL bytes")


@dataclass
class AgentProcess:
    session_key: str
    spec: AgentSpec
    process: subprocess.Popen[bytes]


PopenFactory = Callable[..., subprocess.Popen[bytes]]
WorkdirValidator = Callable[[str], str]


@runtime_checkable
class AgentAdapter(Protocol):
    spec: AgentSpec

    @property
    def active_sessions(self) -> tuple[str, ...]: ...

    def start(self, session_key: str, *, workdir: str) -> AgentProcess: ...

    def send(self, session_key: str, data: str) -> None: ...

    def read_available(self, session_key: str, *, max_bytes: int = 64 * 1024) -> bytes: ...

    def exit_code(self, session_key: str) -> int | None: ...

    def cancel(self, session_key: str, *, timeout: float = 2.0) -> None: ...

    def close(self, session_key: str) -> None: ...

    def close_all(self) -> None: ...


class ProductionAgentAdapter:
    """Owns production agent subprocesses without shell interpretation."""

    def __init__(
        self,
        spec: AgentSpec,
        *,
        popen_factory: PopenFactory = subprocess.Popen,
        max_sessions: int = 8,
        workdir_validator: WorkdirValidator | None = None,
    ) -> None:
        if max_sessions <= 0:
            raise ValueError("max_sessions must be positive")
        self.spec = spec
        self._popen = popen_factory
        self._max_sessions = max_sessions
        self._workdir_validator = workdir_validator
        self._processes: dict[str, AgentProcess] = {}

    @property
    def active_sessions(self) -> tuple[str, ...]:
        return tuple(self._processes)

    def start(self, session_key: str, *, workdir: str) -> AgentProcess:
        self._validate_session_key(session_key)
        if self._workdir_validator is not None:
            workdir = self._workdir_validator(workdir)
        if not os.path.isabs(workdir):
            raise AdapterError("workdir must be absolute")
        existing = self._processes.get(session_key)
        if existing is not None and existing.process.poll() is None:
            return existing
        if existing is not None:
            self.cancel(session_key)
        if len(self._processes) >= self._max_sessions:
            raise AdapterError("maximum active agent sessions reached")

        environment = None
        if self.spec.environment is not None:
            environment = {str(key): str(value) for key, value in self.spec.environment.items()}
        try:
            process = self._popen(
                list(self.spec.command),
                cwd=workdir,
                env=environment,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                shell=False,
                start_new_session=True,
            )
        except OSError as exc:
            raise AdapterError(f"unable to start {self.spec.agent_type}") from exc
        if process.stdin is None or process.stdout is None:
            process.kill()
            raise AdapterError("agent process did not expose stdio pipes")
        record = AgentProcess(session_key=session_key, spec=self.spec, process=process)
        self._processes[session_key] = record
        return record

    def send(self, session_key: str, data: str) -> None:
        record = self._require_active(session_key)
        if not data:
            return
        assert record.process.stdin is not None
        try:
            record.process.stdin.write(data.encode("utf-8"))
            record.process.stdin.flush()
            if record.spec.close_stdin_after_send:
                record.process.stdin.close()
        except (BrokenPipeError, OSError) as exc:
            raise AdapterError("agent stdin is closed") from exc

    def read_available(self, session_key: str, *, max_bytes: int = 64 * 1024) -> bytes:
        if max_bytes <= 0:
            raise ValueError("max_bytes must be positive")
        record = self._require_record(session_key)
        assert record.process.stdout is not None
        selector = selectors.DefaultSelector()
        try:
            selector.register(record.process.stdout, selectors.EVENT_READ)
            if not selector.select(timeout=0):
                return b""
            try:
                return os.read(record.process.stdout.fileno(), max_bytes)
            except BlockingIOError:
                return b""
        finally:
            selector.close()

    def exit_code(self, session_key: str) -> int | None:
        return self._require_record(session_key).process.poll()

    def cancel(self, session_key: str, *, timeout: float = 2.0) -> None:
        record = self._processes.get(session_key)
        if record is None:
            return
        process = record.process
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=timeout)
        self._close_pipes(process)
        self._processes.pop(session_key, None)

    def close(self, session_key: str) -> None:
        self.cancel(session_key)

    def close_all(self) -> None:
        for session_key in tuple(self._processes):
            self.cancel(session_key)

    @staticmethod
    def _close_pipes(process: subprocess.Popen[bytes]) -> None:
        for pipe in (process.stdin, process.stdout):
            if pipe is None:
                continue
            try:
                pipe.close()
            except OSError:
                pass

    def _require_record(self, session_key: str) -> AgentProcess:
        self._validate_session_key(session_key)
        record = self._processes.get(session_key)
        if record is None:
            raise AdapterError("agent session is not known")
        return record

    def _require_active(self, session_key: str) -> AgentProcess:
        record = self._require_record(session_key)
        if record.process.poll() is not None:
            raise AdapterError("agent session is not running")
        return record

    @staticmethod
    def _validate_session_key(session_key: str) -> None:
        if not session_key.strip() or "\x00" in session_key:
            raise ValueError("session_key must be non-empty and NUL-free")
