"""Safe Unix PTY adapter for the production Host terminal channel."""

from __future__ import annotations

import errno
import fcntl
import os
import pty
import selectors
import signal
import struct
import termios
import time
from dataclasses import dataclass
from typing import Callable, Mapping, Protocol, runtime_checkable

from production_adapter import AdapterError


@dataclass(frozen=True)
class PtySpec:
    command: tuple[str, ...]
    environment: Mapping[str, str] | None = None

    def __post_init__(self) -> None:
        if not self.command or any(not part for part in self.command):
            raise ValueError("command must be a non-empty argv tuple")
        if any("\x00" in part for part in self.command):
            raise ValueError("command must not contain NUL bytes")


@dataclass
class PtyProcess:
    session_key: str
    spec: PtySpec
    pid: int
    master_fd: int
    cols: int
    rows: int
    exit_code: int | None = None


PtyFork = Callable[[], tuple[int, int]]
WorkdirValidator = Callable[[str], str]


@runtime_checkable
class TerminalAdapter(Protocol):
    @property
    def active_sessions(self) -> tuple[str, ...]: ...

    def start(
        self,
        session_key: str,
        *,
        workdir: str,
        cols: int = 80,
        rows: int = 24,
    ) -> PtyProcess: ...

    def send(self, session_key: str, data: str) -> None: ...

    def read_available(self, session_key: str, *, max_bytes: int = 64 * 1024) -> bytes: ...

    def resize(self, session_key: str, *, cols: int, rows: int) -> None: ...

    def exit_code(self, session_key: str) -> int | None: ...

    def cancel(self, session_key: str, *, timeout: float = 2.0) -> None: ...

    def close_all(self) -> None: ...


class PtyTerminalAdapter:
    """Own explicit-argv PTYs without shell interpretation."""

    def __init__(
        self,
        spec: PtySpec,
        *,
        fork_factory: PtyFork = pty.fork,
        max_sessions: int = 8,
        workdir_validator: WorkdirValidator | None = None,
    ) -> None:
        if max_sessions <= 0:
            raise ValueError("max_sessions must be positive")
        self.spec = spec
        self._fork = fork_factory
        self._max_sessions = max_sessions
        self._workdir_validator = workdir_validator
        self._processes: dict[str, PtyProcess] = {}

    @property
    def active_sessions(self) -> tuple[str, ...]:
        return tuple(self._processes)

    def start(
        self,
        session_key: str,
        *,
        workdir: str,
        cols: int = 80,
        rows: int = 24,
    ) -> PtyProcess:
        self._validate_session_key(session_key)
        self._validate_geometry(cols, rows)
        if self._workdir_validator is not None:
            workdir = self._workdir_validator(workdir)
        if not os.path.isabs(workdir):
            raise AdapterError("workdir must be absolute")
        if not os.path.isdir(workdir):
            raise AdapterError("workdir must be an existing directory")
        existing = self._processes.get(session_key)
        if existing is not None and self.exit_code(session_key) is None:
            return existing
        if existing is not None:
            self.close(session_key)
        if len(self._processes) >= self._max_sessions:
            raise AdapterError("maximum active terminal sessions reached")

        pid, master_fd = self._fork()
        if pid == 0:
            self._exec_child(workdir)
        try:
            self._set_nonblocking(master_fd)
            record = PtyProcess(
                session_key=session_key,
                spec=self.spec,
                pid=pid,
                master_fd=master_fd,
                cols=cols,
                rows=rows,
            )
            self._processes[session_key] = record
            self._set_geometry(record)
            return record
        except Exception:
            try:
                os.close(master_fd)
            except OSError:
                pass
            self._terminate_pid(pid, timeout=0.2)
            raise

    def send(self, session_key: str, data: str) -> None:
        record = self._require_active(session_key)
        if not data:
            return
        try:
            os.write(record.master_fd, data.encode("utf-8"))
        except (BrokenPipeError, OSError) as exc:
            raise AdapterError("terminal PTY is closed") from exc

    def read_available(self, session_key: str, *, max_bytes: int = 64 * 1024) -> bytes:
        if max_bytes <= 0:
            raise ValueError("max_bytes must be positive")
        record = self._require_record(session_key)
        selector = selectors.DefaultSelector()
        try:
            selector.register(record.master_fd, selectors.EVENT_READ)
            if not selector.select(timeout=0):
                return b""
            try:
                return os.read(record.master_fd, max_bytes)
            except OSError as exc:
                if exc.errno in (errno.EIO, errno.EBADF):
                    return b""
                if exc.errno == errno.EAGAIN:
                    return b""
                raise
        finally:
            selector.close()

    def resize(self, session_key: str, *, cols: int, rows: int) -> None:
        self._validate_geometry(cols, rows)
        record = self._require_active(session_key)
        record.cols = cols
        record.rows = rows
        try:
            self._set_geometry(record)
        except OSError as exc:
            raise AdapterError("unable to resize terminal PTY") from exc
        try:
            os.killpg(record.pid, signal.SIGWINCH)
        except ProcessLookupError:
            pass

    def exit_code(self, session_key: str) -> int | None:
        record = self._require_record(session_key)
        if record.exit_code is not None:
            return record.exit_code
        waited_pid, status = os.waitpid(record.pid, os.WNOHANG)
        if waited_pid == record.pid:
            record.exit_code = os.waitstatus_to_exitcode(status)
        return record.exit_code

    def cancel(self, session_key: str, *, timeout: float = 2.0) -> None:
        record = self._processes.get(session_key)
        if record is None:
            return
        exit_code = self.exit_code(session_key)
        try:
            os.close(record.master_fd)
        except OSError:
            pass
        if exit_code is None:
            self._terminate_pid(record.pid, timeout=timeout)
        else:
            self._reap(record.pid)
        self._processes.pop(session_key, None)

    def close(self, session_key: str) -> None:
        self.cancel(session_key)

    def close_all(self) -> None:
        for session_key in tuple(self._processes):
            self.cancel(session_key)

    def _exec_child(self, workdir: str) -> None:
        try:
            os.chdir(workdir)
            environment = os.environ.copy()
            if self.spec.environment is not None:
                environment.update({str(k): str(v) for k, v in self.spec.environment.items()})
            environment.setdefault("TERM", "xterm-256color")
            os.execvpe(self.spec.command[0], list(self.spec.command), environment)
        except BaseException:
            os._exit(127)

    @staticmethod
    def _set_nonblocking(master_fd: int) -> None:
        flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
        fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    @staticmethod
    def _set_geometry(record: PtyProcess) -> None:
        winsize = struct.pack("HHHH", record.rows, record.cols, 0, 0)
        fcntl.ioctl(record.master_fd, termios.TIOCSWINSZ, winsize)

    def _require_record(self, session_key: str) -> PtyProcess:
        self._validate_session_key(session_key)
        record = self._processes.get(session_key)
        if record is None:
            raise AdapterError("terminal session is not known")
        return record

    def _require_active(self, session_key: str) -> PtyProcess:
        record = self._require_record(session_key)
        if self.exit_code(session_key) is not None:
            raise AdapterError("terminal session is not running")
        return record

    def _close_record(self, session_key: str, record: PtyProcess) -> None:
        try:
            os.close(record.master_fd)
        except OSError:
            pass
        self._processes.pop(session_key, None)

    @staticmethod
    def _reap(pid: int) -> None:
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass

    @staticmethod
    def _terminate_pid(pid: int, *, timeout: float) -> None:
        if timeout < 0:
            raise ValueError("timeout must not be negative")
        PtyTerminalAdapter._signal_process(pid, signal.SIGTERM)
        if PtyTerminalAdapter._wait_for_exit(pid, timeout):
            return
        PtyTerminalAdapter._signal_process(pid, signal.SIGKILL)
        if not PtyTerminalAdapter._wait_for_exit(pid, max(timeout, 0.5)):
            raise AdapterError("unable to terminate terminal PTY process")

    @staticmethod
    def _signal_process(pid: int, sig: signal.Signals) -> None:
        delivered = False
        try:
            os.killpg(pid, sig)
            delivered = True
        except ProcessLookupError:
            pass
        try:
            os.kill(pid, sig)
            delivered = True
        except ProcessLookupError:
            pass
        if not delivered:
            PtyTerminalAdapter._reap(pid)

    @staticmethod
    def _wait_for_exit(pid: int, timeout: float) -> bool:
        deadline = time.monotonic() + timeout
        while True:
            try:
                waited_pid, _ = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                return True
            if waited_pid == pid:
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.01)

    @staticmethod
    def _validate_session_key(session_key: str) -> None:
        if not session_key.strip() or "\x00" in session_key:
            raise ValueError("session_key must be non-empty and NUL-free")

    @staticmethod
    def _validate_geometry(cols: int, rows: int) -> None:
        if not (1 <= cols <= 1000 and 1 <= rows <= 500):
            raise ValueError("terminal geometry is outside supported limits")
