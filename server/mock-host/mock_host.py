#!/usr/bin/env python3
"""HuanHermes Mock Host: Bridge WebSocket + Management REST (stdlib only).

Env:
  HUAN_BRIDGE_HOST (default 0.0.0.0)
  HUAN_BRIDGE_PORT (default 9810)
  HUAN_MGMT_PORT   (default 9820)
  HUAN_BRIDGE_TOKEN
  HUAN_MGMT_TOKEN
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import fcntl
import os
import pty
import select
import struct
import termios
import re
import socket
import struct
import threading
import time
import traceback
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlparse


BRIDGE_HOST = os.environ.get("HUAN_BRIDGE_HOST", "0.0.0.0")
BRIDGE_PORT = int(os.environ.get("HUAN_BRIDGE_PORT", "9810"))
MGMT_PORT = int(os.environ.get("HUAN_MGMT_PORT", "9820"))
BRIDGE_TOKEN = os.environ.get("HUAN_BRIDGE_TOKEN", "dev-bridge-token-change-me")
MGMT_TOKEN = os.environ.get("HUAN_MGMT_TOKEN", "dev-mgmt-token-change-me")
START_TS = time.time()

PROJECTS = [
    {
        "name": "claude-code",
        "agent_type": "claudecode",
        "platforms": ["bridge"],
        "sessions_count": 0,
        "capabilities": [
            "stream",
            "buttons",
            "cancel",
            "workdir",
            "mode",
            "model",
            "tools_visible",
            "terminal",
            "skills_catalog",
            "mcp_catalog",
        ],
        "models": ["claude-sonnet-4", "claude-opus-4"],
        "channels": ["anthropic"],
    },
    {
        "name": "codex",
        "agent_type": "codex",
        "platforms": ["bridge"],
        "sessions_count": 0,
        "capabilities": [
            "stream",
            "buttons",
            "cancel",
            "workdir",
            "mode",
            "model",
            "tools_visible",
            "terminal",
            "skills_catalog",
            "mcp_catalog",
        ],
        "models": ["gpt-5-codex", "o4-mini"],
        "channels": ["openai"],
    },
    {
        "name": "hermes",
        "agent_type": "hermes",
        "platforms": ["bridge"],
        "sessions_count": 0,
        "capabilities": [
            "stream",
            "buttons",
            "cancel",
            "workdir",
            "mode",
            "model",
            "tools_visible",
            "memory_readonly",
            "skills_catalog",
            "mcp_catalog",
            "terminal",
        ],
        "models": ["hermes-default", "hermes-reasoning"],
        "channels": ["hermes"],
        "note": "Mock Hermes — real adapter is ADR-002; not a live Hermes process",
        "adapter": "mock",
        "process": False,
    },
]

SESSIONS: Dict[str, Dict[str, Any]] = {}
SESSIONS_LOCK = threading.Lock()
SESSION_STATE: Dict[str, Dict[str, Any]] = {}
ACTIVE_RUNS: Dict[str, threading.Event] = {}
ACTIVE_LOCK = threading.Lock()

# Readonly mock workspace tree for GET /workspace (console file browser demo).
WORKSPACE_TREE: Dict[str, Any] = {
    "type": "dir",
    "name": "",
    "children": {
        "AGENTS.md": {
            "type": "file",
            "content": "# AGENTS\n\nMock workspace. Host is source of truth.\n",
            "size": 48,
        },
        "README.md": {
            "type": "file",
            "content": "# Demo project\n\nHuanHermes Mock workspace (readonly).\n",
            "size": 52,
        },
        "src": {
            "type": "dir",
            "children": {
                "main.py": {
                    "type": "file",
                    "content": "def main():\n    print('hello from mock workspace')\n\nif __name__ == '__main__':\n    main()\n",
                    "size": 90,
                },
                "util.py": {
                    "type": "file",
                    "content": "def greet(name: str) -> str:\n    return f'hi {name}'\n",
                    "size": 50,
                },
            },
        },
        "docs": {
            "type": "dir",
            "children": {
                "notes.md": {
                    "type": "file",
                    "content": "Console notes.\n- status dashboard\n- prompt history\n- workspace browse\n",
                    "size": 70,
                },
                "protocol.md": {
                    "type": "file",
                    "content": "# Protocol\n\nBridge WS + Management REST.\nSee repo docs/protocol (Host owns runtime).\n",
                    "size": 90,
                },
            },
        },
        "hermes": {
            "type": "dir",
            "children": {
                "README.md": {
                    "type": "file",
                    "content": (
                        "# Hermes project (mock)\n\n"
                        "App is console-only. Real Hermes agent loop stays on Host (ADR-002).\n\n"
                        "## Status\n\n"
                        "- adapter: mock\n"
                        "- process: false\n"
                    ),
                    "size": 160,
                },
                "AGENTS.md": {
                    "type": "file",
                    "content": (
                        "# Hermes agents\n\n"
                        "Mock catalog only — Host will map Bridge → process later.\n"
                    ),
                    "size": 80,
                },
                "skills": {
                    "type": "dir",
                    "children": {
                        "hermes-agent.md": {
                            "type": "file",
                            "content": "Skill stub: hermes-agent (catalog surface).\n",
                            "size": 48,
                        },
                    },
                },
            },
        },
    },
}



# ── Mock terminal command catalog (lockstep source of truth) ──
# help / which / type all derive from MOCK_TERM_COMMANDS.
# Handlers remain in _handle_terminal_input; registry maps name→doc for discovery.
MOCK_TERM_COMMANDS: List[str] = [
    "ls", "pwd", "cd", "cat", "head", "tail", "wc", "echo", "env", "date",
    "uname", "hostname", "id", "clear", "mkdir", "stty", "whoami", "help", "tree", "df",
    "free", "ps", "uptime", "stat", "du", "basename", "dirname", "realpath", "which", "true",
    "false", "printf", "sleep", "touch", "history", "grep", "find", "seq", "sort", "export",
    "uniq", "cut", "nl", "fold", "tr", "rev", "cmp", "yes", "tee", "xargs",
    "hexdump", "xxd", "od", "jq", "file", "type", "expr", "test", "factor", "bc",
    "nproc", "arch", "getconf", "numfmt", "logname", "groups", "printenv", "users", "tty", "who",
    "w", "last", "cal", "lscpu", "fmt", "shuf", "paste", "column", "comm", "join",
    "split", "getent", "locale", "umask", "readlink", "cksum", "sum", "expand", "unexpand", "tac",
    "namei", "dir", "vdir", "tsort", "pathchk", "mktemp", "sync", "link", "ln", "truncate",
    "install", "shred", "timeout", "nice", "nohup", "watch", "stdbuf", "flock", "ionice", "taskset",
    "prlimit", "chroot", "unshare", "nsenter", "setpriv", "capsh", "runcon", "ldd", "ldconfig", "uuidgen",
    "rmdir", "mkfifo", "getopt", "strings", "csplit", "diff", "patch", "sdiff", "pr", "dircolors",
    "tput", "tset", "tabs", "script", "scriptreplay", "infocmp", "toe", "reset", "resize", "login",
    "mesg", "write", "wall", "newgrp", "su", "sudo", "chfn", "chsh", "passwd", "lastlog",
    "lastb", "faillog", "chage", "ulimit", "finger", "nologin", "unset", "alias", "unalias", "kill",
    "jobs", "bg", "fg", "less", "more", "awk", "sed", "cp", "mv", "rm",
    "chmod", "chown", "chgrp", "bash", "sh", "exit", "logout", "source", "set", "curl",
    "wget", "ssh", "scp", "rsync", "ping", "tar", "gzip", "gunzip", "zip", "unzip",
    "ip", "netstat", "traceroute",
    "at", "base32", "base64", "cron", "crontab", "dd", "diff3", "fdisk", "groupadd", "groupdel", "info", "lsblk", "mail", "man", "md5sum", "mount", "nano", "screen", "service", "sha1sum", "sha224sum", "sha256sum", "sha384sum", "sha512sum", "systemctl", "tmux", "umount", "useradd", "userdel", "usermod", "vi",
]

MOCK_TERM_KNOWN = set(MOCK_TERM_COMMANDS)
MOCK_TERM_BUILTINS = set(MOCK_TERM_COMMANDS)

# name → short doc (discovery)
MOCK_TERM_DOCS: Dict[str, str] = {name: f"mock builtin: {name}" for name in MOCK_TERM_COMMANDS}

# Table-driven simple handlers: name → (body, exit_code)
# Complex commands stay in the _handle_terminal_input elif chain.
# Registry is checked first; matching names short-circuit the chain.
MOCK_TERM_FIXED: Dict[str, Tuple[str, int]] = {
    # identity / system
    "whoami": ("huanhermes-mock\n", 0),
    "arch": ("x86_64\n", 0),
    "nproc": ("4\n", 0),
    "logname": ("huan\n", 0),
    "users": ("huan\n", 0),
    "groups": ("huan sudo docker\n", 0),
    "tty": ("/dev/pts/0\n", 0),
    "sync": ("", 0),
    "true": ("", 0),
    "false": ("", 1),
    "reset": ("\n", 0),
    "logout": ("logout\n", 0),
    "exit": ("exit\n", 0),
    "bash": ("", 0),
    "sh": ("", 0),
    "unalias": ("", 0),
    "unset": ("", 0),
    "mesg": ("is y\n", 0),
    "uuidgen": ("00000000-0000-4000-8000-000000000001\n", 0),
    "dircolors": ("LS_COLORS='*.py=01;32:'\n", 0),
    "toe": ("xterm-256color\nvt100\nansi\n", 0),
    "resize": ("COLUMNS=80;\nLINES=24;\nexport COLUMNS LINES;\n", 0),
    "nologin": ("This account is currently not available.\n", 1),
    "login": ("login: (mock) not a real login\n", 1),
    "chsh": ("chsh: (mock) not permitted\n", 1),
    "passwd": ("passwd: (mock) Authentication token manipulation error\n", 1),
    "chage": ("chage: (mock) permission denied\n", 1),
    "chfn": ("chfn: (mock) not permitted\n", 1),
    "su": ("su: (mock) Authentication failure\n", 1),
    "sudo": ("sudo: (mock) a password is required\n", 1),
    "newgrp": ("newgrp: (mock) not permitted\n", 1),
    "vi": ("vi: (mock) not available in demo mode\n", 1),
    "nano": ("nano: (mock) not available in demo mode\n", 1),
    "screen": ("screen: (mock) not available in demo mode\n", 1),
    "tmux": ("tmux: (mock) not available in demo mode\n", 1),
    "cron": ("cron: (mock) not available in demo mode\n", 1),
    "mail": ("mail: (mock) not available in demo mode\n", 1),
    # fixed tables / dumps
    "uptime": (" 12:00:00 up 3 days,  4:56,  1 user,  load average: 0.10, 0.20, 0.30\n", 0),
    "hostname": ("huanhermes-mock\n", 0),
    "cal": (
        "     July 2026\n"
        "Su Mo Tu We Th Fr Sa\n"
        "          1  2  3  4\n"
        " 5  6  7  8  9 10 11\n"
        "12 13 14 15 16 17 18\n"
        "19 20 21 22 23 24 25\n"
        "26 27 28 29 30 31\n",
        0,
    ),
    "base32": ("JBSWY3DPEBLW64TMMQ======\n", 0),
    "sha224sum": ("0" * 56 + "  -\n", 0),
    "sha384sum": ("0" * 96 + "  -\n", 0),
    "sha512sum": ("0" * 128 + "  -\n", 0),
    "pr": ("\n\n", 0),
    "bg": ("[1]+ sleep 100 &\n", 0),
    "fg": ("[1]+ sleep 100\n", 0),
    "jobs": ("[1]+  Stopped                 vim\n[2]-  Running                 sleep 100 &\n", 0),
    "lastb": (
        "huan     pts/0        127.0.0.1        Mon Jul 18 07:00 - 07:01  (00:01)\n"
        "\n"
        "btmp begins Mon Jul 18 00:00:01 2026\n",
        0,
    ),
    "faillog": (
        "Login       Failures Maximum Latest\n"
        "huan              0       0   **Never logged in**\n",
        0,
    ),
    "lastlog": (
        "Username         Port     From             Latest\n"
        "huan             pts/0    127.0.0.1        Mon Jul 18 07:00:00 +0000 2026\n",
        0,
    ),
    "ldd": ("\tlinux-vdso.so.1 (0x0000)\n\tlibc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x0000)\n", 0),
    "ldconfig": ("\tlibc.so.6 (libc6,x86-64) => /lib/x86_64-linux-gnu/libc.so.6\n", 0),
    "capsh": ("Current: =ep\nBounding set: =ep\n", 0),
    "lsblk": (
        "NAME  MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT\n"
        "sda     8:0    0  40G  0 disk\n"
        "└─sda1  8:1    0  40G  0 part /\n",
        0,
    ),
    "ip": (
        "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536\n"
        "    inet 127.0.0.1/8 scope host lo\n"
        "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n"
        "    inet 10.0.0.2/24 scope global eth0\n",
        0,
    ),
    "netstat": (
        "Proto Recv-Q Send-Q Local Address           Foreign Address         State\n"
        "tcp        0      0 0.0.0.0:9810            0.0.0.0:*               LISTEN\n"
        "tcp        0      0 0.0.0.0:9820            0.0.0.0:*               LISTEN\n",
        0,
    ),
    "finger": (
        "Login     Name       Tty      Idle  Login Time   Office\n"
        "huan      Huan Mock  pts/0          Jul 18 07:00 (mock)\n",
        0,
    ),
    "w": (
        " 12:00:00 up 3 days,  4:56,  1 user,  load average: 0.10, 0.20, 0.30\n"
        "USER     TTY      FROM             LOGIN@   IDLE   JCPU   PCPU WHAT\n"
        "huan     pts/0    127.0.0.1        07:00    0.00s  0.10s  0.01s mock\n",
        0,
    ),
    "who": ("huan pts/0 2026-07-18 07:00 (mock)\n", 0),
    "last": (
        "huan     pts/0        127.0.0.1        Mon Jul 18 07:00   still logged in\n"
        "\n"
        "wtmp begins Mon Jul  1 00:00:01 2026\n",
        0,
    ),
    "lscpu": (
        "Architecture:        x86_64\n"
        "CPU(s):              4\n"
        "Model name:          HuanHermes Mock CPU\n"
        "Thread(s) per core:  1\n"
        "Core(s) per socket:  4\n",
        0,
    ),
    "df": (
        "Filesystem     1K-blocks    Used Available Use% Mounted on\n"
        "/dev/sda1       41943040 8388608  33554432  20% /\n"
        "tmpfs             524288   1024    523264   1% /tmp\n",
        0,
    ),
    "free": (
        "              total        used        free      shared  buff/cache   available\n"
        "Mem:        5939200     2100000     1800000       12000     2039200     3600000\n"
        "Swap:             0           0           0\n",
        0,
    ),
    "ps": (
        "  PID TTY          TIME CMD\n"
        "    1 ?        00:00:01 systemd\n"
        "   42 pts/0    00:00:00 mock_host\n"
        "   99 pts/0    00:00:00 ps\n",
        0,
    ),
}

# Callable handlers for light arg-aware demos: (raw_data, lower) -> Optional[(body, exit)]
TermHandler = Callable[[str, str], Optional[Tuple[str, int]]]
MOCK_TERM_HANDLERS: Dict[str, TermHandler] = {}


def _reg_fixed() -> None:
    """Install fixed-output handlers from MOCK_TERM_FIXED."""
    for name, (body, code) in MOCK_TERM_FIXED.items():
        def _make(b: str, c: int) -> TermHandler:
            def _h(_raw: str, _lower: str) -> Optional[Tuple[str, int]]:
                return b, c
            return _h
        MOCK_TERM_HANDLERS[name] = _make(body, code)


def _reg(name: str, fn: TermHandler) -> None:
    MOCK_TERM_HANDLERS[name] = fn


def _reg_many(names: List[str], fn: TermHandler) -> None:
    for n in names:
        MOCK_TERM_HANDLERS[n] = fn


def mock_term_help_commands() -> str:
    """Comma-separated command list for help output (stable order)."""
    return ", ".join(MOCK_TERM_COMMANDS)


def mock_term_registry() -> Dict[str, str]:
    """name → short doc. Used by which/type discovery & table-driven handlers."""
    return dict(MOCK_TERM_DOCS)


def mock_term_dispatch(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    """Try table-driven handler. Returns (body, exit_code) or None to fall through."""
    if not lower:
        return None
    cmd0 = lower.split()[0]
    # strip leading ./ 
    if cmd0.startswith("./"):
        cmd0 = cmd0[2:]
    fn = MOCK_TERM_HANDLERS.get(cmd0)
    if fn is None:
        return None
    return fn(raw, lower)


# Register fixed table first
_reg_fixed()


# Light arg-aware registry handlers (still simple demos)
def _h_echo(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    # leave complex echo (with escapes) to elif chain if needed — simple path:
    if lower == "echo" or lower.startswith("echo "):
        text = raw.strip()[4:].lstrip() if lower.startswith("echo") else ""
        # strip surrounding quotes lightly
        if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
            text = text[1:-1]
        return text + "\n", 0
    return None


def _h_which(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    name = raw.strip()[6:].strip() if lower.startswith("which ") else ""
    if not name:
        return "which: missing operand\n", 1
    if name.split()[0] in MOCK_TERM_KNOWN:
        return f"/usr/bin/{name.split()[0]}\n", 0
    return f"which: no {name} in ($PATH)\n", 1


def _h_type(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    name = raw.strip()[4:].strip() if lower.startswith("type ") else ("" if lower == "type" else "")
    if lower == "type" or not name:
        return "type: missing operand\n", 1
    base = name.split()[0]
    if base in MOCK_TERM_BUILTINS:
        return f"{base} is a shell builtin\n", 0
    return f"type: {base}: not found\n", 1


def _h_uname(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    # bare uname → Linux; -a full; -r release; else Linux
    args = raw.strip().split()[1:] if lower.startswith("uname") else []
    if not args:
        return "Linux\n", 0
    flag = args[0]
    if flag in ("-a", "--all"):
        return "Linux huanhermes-mock 6.1.0-mock #1 SMP x86_64 GNU/Linux\n", 0
    if flag in ("-r", "--kernel-release"):
        return "6.1.0-mock\n", 0
    if flag in ("-m", "--machine"):
        return "x86_64\n", 0
    if flag in ("-n", "--nodename"):
        return "huanhermes-mock\n", 0
    if flag in ("-s", "--kernel-name"):
        return "Linux\n", 0
    return "Linux\n", 0


def _h_id(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:] if lower.startswith("id") else []
    joined = " ".join(args)
    if not args:
        return "uid=1000(mock) gid=1000(mock) groups=1000(mock)\n", 0
    if joined in ("-u",) or args == ["-u"]:
        return "1000\n", 0
    if joined in ("-g",) or args == ["-g"]:
        return "1000\n", 0
    if "-un" in args or (len(args) >= 2 and "-u" in args and "-n" in args) or joined == "-un":
        return "mock\n", 0
    return "uid=1000(mock) gid=1000(mock) groups=1000(mock)\n", 0


def _h_strings(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "strings: missing operand\n", 1
    return "hello\nworld\n", 0


def _h_csplit(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "csplit: missing operand\n", 1
    return "0\n", 0


def _h_kill(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "kill: usage: kill [-s sigspec | -n signum | -sigspec] pid | jobspec ... or kill -l [sigspec]\n", 1
    return "", 0


def _h_ping(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "ping: usage error: Destination address required\n", 1
    host = args[0]
    return (
        f"PING {host} (127.0.0.1) 56(84) bytes of data.\n"
        f"64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.05 ms\n"
        f"\n--- {host} ping statistics ---\n"
        f"1 packets transmitted, 1 received, 0% packet loss\n",
        0,
    )


def _h_ssh(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "usage: ssh [-46AaCfGgKkMNnqsTtVvXxYy] ... destination [command]\n", 255
    return f"ssh: connect to host {args[0]} port 22: Connection refused\n", 255


def _h_silent_need_args(usage: str, code: int = 1) -> TermHandler:
    def _h(raw: str, lower: str) -> Optional[Tuple[str, int]]:
        args = raw.strip().split()[1:]
        if not args:
            return usage, code
        return "", 0
    return _h


def _h_demo_unavailable(name: str) -> TermHandler:
    def _h(raw: str, lower: str) -> Optional[Tuple[str, int]]:
        return f"{name}: (mock) not available in demo mode\n", 1
    return _h


_reg("which", _h_which)
_reg("type", _h_type)
_reg("uname", _h_uname)
_reg("id", _h_id)
_reg("strings", _h_strings)
_reg("csplit", _h_csplit)
_reg("kill", _h_kill)
_reg("ping", _h_ping)
_reg("ssh", _h_ssh)

# silent-with-args / usage-bare family
_reg("cp", _h_silent_need_args("cp: missing file operand\n"))
_reg("mv", _h_silent_need_args("mv: missing file operand\n"))
_reg("rm", _h_silent_need_args("rm: missing operand\n"))
_reg("chmod", _h_silent_need_args("chmod: missing operand\n"))
_reg("chown", _h_silent_need_args("chown: missing operand\n"))
_reg("chgrp", _h_silent_need_args("chgrp: missing operand\n"))
_reg("touch", _h_silent_need_args("touch: missing file operand\n"))
_reg("rmdir", _h_silent_need_args("rmdir: missing operand\n"))
_reg("mkfifo", _h_silent_need_args("mkfifo: missing operand\n"))
_reg("link", _h_silent_need_args("link: missing file operand\n"))
_reg("ln", _h_silent_need_args("ln: missing file operand\n"))
_reg("install", _h_silent_need_args("install: missing file operand\n"))
_reg("shred", _h_silent_need_args("shred: missing file operand\n"))
_reg("chroot", _h_silent_need_args("chroot: missing operand\n"))
_reg("runcon", _h_silent_need_args("runcon: missing operand\n"))
_reg("patch", _h_silent_need_args("patch: missing operand\n"))
_reg("useradd", _h_silent_need_args("useradd: missing operand\n"))
_reg("userdel", _h_silent_need_args("userdel: missing operand\n"))
_reg("usermod", _h_silent_need_args("usermod: missing operand\n"))
_reg("groupadd", _h_silent_need_args("groupadd: missing operand\n"))
_reg("groupdel", _h_silent_need_args("groupdel: missing operand\n"))
_reg("crontab", _h_silent_need_args("crontab: usage error\n"))
_reg("at", _h_silent_need_args("at: missing operand\n"))
_reg("umount", _h_silent_need_args("umount: missing operand\n"))
_reg("dd", _h_silent_need_args("dd: missing operand\n"))
_reg("fdisk", _h_silent_need_args("fdisk: missing operand\n"))
_reg("service", _h_silent_need_args("service: missing operand\n"))
_reg("systemctl", _h_silent_need_args("systemctl: missing operand\n"))
_reg("curl", _h_silent_need_args("curl: try 'curl --help' for more information\n", 2))
_reg("wget", _h_silent_need_args("wget: missing URL\n"))
_reg("scp", _h_silent_need_args("usage: scp [-46ABCOpqRrsTv] ...\n"))
_reg("rsync", _h_silent_need_args("rsync: missing operand\n"))
_reg("tar", _h_silent_need_args("tar: Cowardly refusing to create an empty archive\n", 2))
_reg("gzip", _h_silent_need_args("gzip: compressed data not written to a terminal.\n"))
_reg("gunzip", _h_silent_need_args("gunzip: compressed data not written to a terminal.\n"))
_reg("zip", _h_silent_need_args("zip error: Nothing to do!\n", 12))
_reg("unzip", _h_silent_need_args("unzip:  missing archive name\n"))
_reg("awk", _h_silent_need_args("Usage: awk [OPTION]... [program] [file]\n"))
_reg("sed", _h_silent_need_args("Usage: sed [OPTION]... {script} [input-file]\n"))
_reg("source", _h_silent_need_args("source: filename argument required\n"))
_reg("nice", _h_silent_need_args("nice: missing operand\n"))
_reg("nohup", _h_silent_need_args("nohup: missing operand\n"))
_reg("stdbuf", _h_silent_need_args("stdbuf: missing operand\n"))
_reg("timeout", _h_silent_need_args("timeout: missing operand\n"))
_reg("taskset", _h_silent_need_args("taskset: missing operand\n"))
_reg("unshare", _h_silent_need_args("unshare: missing operand\n"))
_reg("nsenter", _h_silent_need_args("nsenter: missing operand\n"))
_reg("setpriv", _h_silent_need_args("setpriv: missing operand\n"))
_reg("man", _h_silent_need_args("What manual page do you want?\n", 16))
_reg("info", _h_silent_need_args("info: missing menu item\n"))

# write/wall need args message
def _h_write(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "write: missing user argument\n", 1
    return "", 0

def _h_wall(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    return "", 0

_reg("write", _h_write)
_reg("wall", _h_wall)

def _h_alias(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "alias ll='ls -la'\nalias la='ls -A'\nalias l='ls -CF'\n", 0
    return "", 0

_reg("alias", _h_alias)

def _h_set(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return (
            "BASH=/bin/bash\n"
            "HOME=/home/mock\n"
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n"
            "SHELL=/bin/bash\n"
            "USER=mock\n"
            "PWD=/workspace\n",
            0,
        )
    return "", 0

_reg("set", _h_set)

def _h_ulimit(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    if lower in ("ulimit", "ulimit -a"):
        return (
            "core file size          (blocks, -c) 0\n"
            "data seg size           (kbytes, -d) unlimited\n"
            "scheduling priority             (-e) 0\n"
            "file size               (blocks, -f) unlimited\n"
            "pending signals                 (-i) 15127\n"
            "max locked memory       (kbytes, -l) 65536\n"
            "max memory size         (kbytes, -m) unlimited\n"
            "open files                      (-n) 1024\n"
            "pipe size            (512 bytes, -p) 8\n"
            "POSIX message queues     (bytes, -q) 819200\n"
            "real-time priority              (-r) 0\n"
            "stack size              (kbytes, -s) 8192\n"
            "cpu time               (seconds, -t) unlimited\n"
            "max user processes              (-u) 15127\n"
            "virtual memory          (kbytes, -v) unlimited\n"
            "file locks                      (-x) unlimited\n",
            0,
        )
    return "unlimited\n", 0

_reg("ulimit", _h_ulimit)

def _h_locale(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "LANG=C.UTF-8\nLC_ALL=C.UTF-8\n", 0
    if args[0] == "-a":
        return "C\nC.UTF-8\nen_US.UTF-8\n", 0
    return "locale: usage: locale [-a]\n", 1

_reg("locale", _h_locale)

def _h_umask(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "0022\n", 0
    mode = args[0]
    if re.fullmatch(r"0?[0-7]{3}", mode):
        return "", 0
    return f"umask: {mode}: invalid mode\n", 1

_reg("umask", _h_umask)

def _h_printenv(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    demo = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/home/huan",
        "USER": "huan",
        "SHELL": "/bin/bash",
        "LANG": "C.UTF-8",
        "PWD": "/workspace",
    }
    args = raw.strip().split()[1:]
    if not args:
        return "".join(f"{k}={v}\n" for k, v in demo.items()), 0
    key = args[0]
    if key in demo:
        return demo[key] + "\n", 0
    return "", 1

_reg("printenv", _h_printenv)

def _h_getconf(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "getconf: missing operand\n", 1
    key = args[0]
    table = {
        "NPROCESSORS_ONLN": "4",
        "_NPROCESSORS_ONLN": "4",
        "PAGE_SIZE": "4096",
        "PAGESIZE": "4096",
    }
    if key in table:
        return table[key] + "\n", 0
    return f"getconf: {key}: unknown variable\n", 1

_reg("getconf", _h_getconf)

def _h_diff(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if len(args) < 2:
        return "diff: missing operand\n", 1
    return "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n", 1

def _h_sdiff(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if len(args) < 2:
        return "sdiff: missing operand\n", 1
    return "old\t\t\t\tnew\n", 1

def _h_diff3(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if len(args) < 3:
        return "diff3: missing operand\n", 1
    return "====\n1:1c\n  a\n2:1c\n  b\n3:1c\n  c\n", 1

_reg("diff", _h_diff)
_reg("sdiff", _h_sdiff)
_reg("diff3", _h_diff3)

def _h_mount(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return (
            "/dev/sda1 on / type ext4 (rw,relatime)\n"
            "tmpfs on /tmp type tmpfs (rw,nosuid,nodev)\n",
            0,
        )
    return "", 0

_reg("mount", _h_mount)

def _h_traceroute(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "traceroute: missing host operand\n", 1
    host = args[0]
    return (
        f"traceroute to {host} (127.0.0.1), 30 hops max\n"
        f" 1  127.0.0.1  0.05 ms  0.04 ms  0.03 ms\n",
        0,
    )

_reg("traceroute", _h_traceroute)

def _h_yes(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    word = args[0] if args else "y"
    return (word + "\n") * 5, 0

_reg("yes", _h_yes)

def _h_factor(raw: str, lower: str) -> Optional[Tuple[str, int]]:
    args = raw.strip().split()[1:]
    if not args:
        return "factor: missing operand\n", 1
    try:
        n = int(args[0])
    except ValueError:
        return "factor: invalid number\n", 1
    if n <= 1:
        return f"{n}:\n", 0
    if abs(n) > 10**12:
        return "factor: number too large for mock\n", 1
    x = abs(n)
    factors = []
    d = 2
    while d * d <= x:
        while x % d == 0:
            factors.append(str(d))
            x //= d
        d += 1 if d == 2 else 2
    if x > 1:
        factors.append(str(x))
    return f"{n}: " + " ".join(factors) + "\n", 0

_reg("factor", _h_factor)


def _ws_walk_files(node: Optional[Dict[str, Any]], prefix: str = "") -> List[Tuple[str, Dict[str, Any]]]:
    """Yield (relpath, file_node) for all files under node."""
    out: List[Tuple[str, Dict[str, Any]]] = []
    if not node or not isinstance(node, dict):
        return out
    if node.get("type") == "file":
        out.append((prefix, node))
        return out
    kids = node.get("children") or {}
    if not isinstance(kids, dict):
        return out
    for name, child in sorted(kids.items()):
        p = f"{prefix}/{name}" if prefix else name
        out.extend(_ws_walk_files(child, p))
    return out

def _ws_resolve(path: str) -> Tuple[Optional[Dict[str, Any]], str]:
    """Resolve relative path under WORKSPACE_TREE. Returns (node, cleaned_path)."""
    raw = (path or "").strip().replace("\\", "/")
    while raw.startswith("./"):
        raw = raw[2:]
    if raw.startswith("/"):
        raw = raw[1:]
    if ".." in raw.split("/"):
        return None, raw
    node: Dict[str, Any] = WORKSPACE_TREE
    if not raw or raw in {".", "/"}:
        return node, ""
    parts = [p for p in raw.split("/") if p]
    for part in parts:
        kids = node.get("children") if isinstance(node, dict) else None
        if not isinstance(kids, dict) or part not in kids:
            return None, raw
        node = kids[part]
    return node, "/".join(parts)


def workspace_list(path: str = "") -> Dict[str, Any]:
    node, cleaned = _ws_resolve(path)
    if node is None:
        return {"error": "not found", "path": path}
    if node.get("type") == "file":
        return {
            "path": cleaned,
            "type": "file",
            "name": cleaned.split("/")[-1] if cleaned else "",
            "size": node.get("size", len(node.get("content") or "")),
            "content": node.get("content") or "",
        }
    kids = node.get("children") or {}
    entries = []
    for name, child in sorted(kids.items(), key=lambda x: (x[1].get("type") != "dir", x[0])):
        entries.append(
            {
                "name": name,
                "type": child.get("type"),
                "size": child.get("size") if child.get("type") == "file" else None,
            }
        )
    parent = ""
    if cleaned:
        parts = cleaned.split("/")
        parent = "/".join(parts[:-1])
    return {
        "path": cleaned,
        "type": "dir",
        "parent": parent,
        "entries": entries,
    }


def workspace_git_status() -> Dict[str, Any]:
    return {
        "branch": "main",
        "clean": False,
        "files": [
            {"path": "src/main.py", "status": "M"},
            {"path": "docs/notes.md", "status": "?"},
            {"path": "docs/protocol.md", "status": "A"},
            {"path": "hermes/README.md", "status": "A"},
            {"path": "hermes/AGENTS.md", "status": "A"},
        ],
        "note": "Mock git status — readonly demo (includes hermes/ tree)",
    }




# Host-side memory catalog (readonly demo for console; Host is source of truth)
MEMORY_ENTRIES: List[Dict[str, Any]] = [
    {
        "id": "mem-user-pref-lang",
        "scope": "global",
        "type": "user",
        "title": "Preferred language",
        "content": "User prefers concise Chinese UI labels with English technical terms.",
        "confidence": "high",
        "updated_at": time.time() - 3600,
        "tags": ["preference", "i18n"],
    },
    {
        "id": "mem-project-layout",
        "scope": "project",
        "type": "project",
        "title": "Repo layout",
        "content": "HuanHermes App is console-only; Mock Host owns sessions and workspace demo tree.",
        "confidence": "high",
        "project": "claude-code",
        "updated_at": time.time() - 7200,
        "tags": ["architecture"],
    },
    {
        "id": "mem-feedback-brief",
        "scope": "global",
        "type": "feedback",
        "title": "Response style",
        "content": "Prefer short summaries + tables; avoid long preambles.",
        "confidence": "medium",
        "updated_at": time.time() - 86400,
        "tags": ["style"],
    },
    {
        "id": "mem-hermes-console",
        "scope": "project",
        "type": "project",
        "title": "Hermes console boundary",
        "content": "App is console-only; Hermes agent loop stays on Host (ADR-002 mock).",
        "confidence": "high",
        "project": "hermes",
        "updated_at": time.time() - 1800,
        "tags": ["hermes", "architecture", "console"],
    },
    {
        "id": "mem-hermes-pairing",
        "scope": "global",
        "type": "policy",
        "title": "Pairing tokens",
        "content": "Pairing URI and paste card must never embed tokens.",
        "confidence": "high",
        "updated_at": time.time() - 900,
        "tags": ["security", "pairing", "hermes"],
    },
]

CRON_JOBS: List[Dict[str, Any]] = [
    {
        "id": "cron-daily-status",
        "name": "Daily host status",
        "kind": "prompt",
        "schedule": "0 9 * * *",
        "enabled": True,
        "next_run_at": time.time() + 3600,
        "last_run_at": time.time() - 86400,
        "last_status": "ok",
        "description": "Ask agent for a short host health summary",
    },
    {
        "id": "cron-git-digest",
        "name": "Workspace git digest",
        "kind": "http",
        "schedule": "every 6h",
        "enabled": True,
        "next_run_at": time.time() + 7200,
        "last_run_at": time.time() - 20000,
        "last_status": "ok",
        "description": "GET /workspace/git and store summary (mock)",
    },
    {
        "id": "cron-cleanup",
        "name": "Session hygiene note",
        "kind": "bash",
        "schedule": "0 3 * * 0",
        "enabled": False,
        "next_run_at": None,
        "last_run_at": time.time() - 604800,
        "last_status": "skipped",
        "description": "Disabled mock job — Host would run cleanup scripts",
    },
    {
        "id": "cron-hermes-memory",
        "name": "Hermes memory digest",
        "kind": "prompt",
        "schedule": "every 12h",
        "enabled": True,
        "project": "hermes",
        "next_run_at": time.time() + 12 * 3600,
        "last_run_at": time.time() - 12 * 3600,
        "last_status": "ok",
        "description": "Mock: summarize hermes project memories (ADR-002 · no real process)",
        "tags": ["hermes", "memory"],
    },
    {
        "id": "cron-hermes-skills-scan",
        "name": "Hermes skills catalog scan",
        "kind": "prompt",
        "schedule": "0 8 * * 1",
        "enabled": False,
        "project": "hermes",
        "next_run_at": None,
        "last_run_at": time.time() - 7 * 86400,
        "last_status": "skipped",
        "description": "Disabled mock: refresh skills list for Hermes project",
        "tags": ["hermes", "skills"],
    },
]

MOCK_DIFFS: Dict[str, str] = {
    "README.md": """--- a/README.md
+++ b/README.md
@@ -1,5 +1,8 @@
 # Demo Workspace
-Placeholder readme
+Mock workspace for HuanHermes console.
+
+Host is the source of truth; App is remote control only.
""",
    "src/main.py": """--- a/src/main.py
+++ b/src/main.py
@@ -1,4 +1,7 @@
 def main():
-    print("hello")
+    print("hello from mock workspace")
+    # demo change for diff viewer
 
 if __name__ == "__main__":
     main()
""",
    "hermes/README.md": """--- /dev/null
+++ b/hermes/README.md
@@ -0,0 +1,8 @@
+# Hermes project (mock)
+
+App is console-only. Real Hermes agent loop stays on Host (ADR-002).
+
+## Status
+
+- adapter: mock
+- process: false
""",
    "docs/protocol.md": """--- /dev/null
+++ b/docs/protocol.md
@@ -0,0 +1,5 @@
+# Protocol
+
+Bridge WS + Management REST.
+See repo docs/protocol (Host owns runtime).
""",
}



# Recent host activity ring buffer (readonly console feed)
ACTIVITY_EVENTS: List[Dict[str, Any]] = []
ACTIVITY_LOCK = threading.Lock()
ACTIVITY_MAX = 100



# Host log lines (readonly console feed)
HOST_LOGS: list[dict] = []
HOST_LOGS_LOCK = threading.Lock()
HOST_LOGS_MAX = 200


def host_log(level: str, message: str, **extra) -> None:
    entry = {
        "ts": int(extra.pop("ts", time.time())),
        "level": level,
        "message": message,
        **extra,
    }
    with HOST_LOGS_LOCK:
        HOST_LOGS.append(entry)
        del HOST_LOGS[: max(0, len(HOST_LOGS) - HOST_LOGS_MAX)]


def seed_host_logs() -> None:
    """Idempotent demo log lines for Logs screen."""
    with HOST_LOGS_LOCK:
        if HOST_LOGS:
            return
    samples = [
        ("info", "Mock Host listening (bridge+mgmt)", "mock-host"),
        ("info", "Hermes adapter=mock (ADR-002) — no live process", "hermes"),
        ("debug", "Terminal geometry default 80x24", "terminal"),
        ("warn", "Pairing URI must never embed tokens", "bridge"),
        ("info", "Activity seed events ready", "mock-host"),
        ("info", "Session channel accepted", "session"),
        ("debug", "Bridge ping/pong ok", "bridge"),
        ("error", "Simulated tool timeout (demo)", "hermes"),
        ("warn", "Workspace readonly for console", "session"),
        ("info", "Logs source filter demo seed", "mock-host"),
    ]
    now = int(time.time())
    for i, (level, msg, src) in enumerate(samples):
        host_log(level, msg, source=src, ts=now - (len(samples) - i) * 15)


seed_host_logs()


def activity_push(kind: str, summary: str, **extra: Any) -> None:
    evt = {
        "id": f"act-{uuid.uuid4().hex[:10]}",
        "ts": time.time(),
        "kind": kind,
        "summary": summary,
        **extra,
    }
    # defaults for console filter chips when caller omits
    if "level" not in evt:
        k = (kind or "").lower()
        if "error" in k or "fail" in k:
            evt["level"] = "error"
        elif "warn" in k or "security" in k:
            evt["level"] = "warn"
        elif "debug" in k or "geometry" in k:
            evt["level"] = "debug"
        else:
            evt["level"] = "info"
    if "source" not in evt:
        k = (kind or "").lower()
        if "hermes" in k:
            evt["source"] = "hermes"
        elif "bridge" in k:
            evt["source"] = "bridge"
        elif "terminal" in k:
            evt["source"] = "terminal"
        elif "session" in k or "chat" in k:
            evt["source"] = "session"
        else:
            evt["source"] = "mock-host"
    with ACTIVITY_LOCK:
        ACTIVITY_EVENTS.append(evt)
        if len(ACTIVITY_EVENTS) > ACTIVITY_MAX:
            del ACTIVITY_EVENTS[: len(ACTIVITY_EVENTS) - ACTIVITY_MAX]




def seed_demo_activity() -> None:
    """Idempotent demo events for Host activity screen (P4 console depth)."""
    with ACTIVITY_LOCK:
        if ACTIVITY_EVENTS:
            return
    samples = [
        ("host.started", "Mock Host ready", "info", "mock-host"),
        ("hermes.adapter.mock", "Hermes project uses mock adapter (ADR-002)", "info", "hermes"),
        ("bridge.listening", "Bridge WebSocket accepting console clients", "info", "bridge"),
        ("terminal.geometry", "Default geometry 80x24 (client may resize)", "debug", "terminal"),
        ("security.pairing", "Pairing URI must never embed tokens", "warn", "session"),
        ("session.seed", "Demo session catalog loaded", "info", "session"),
    ]
    for kind, summary, level, source in samples:
        activity_push(kind, summary, source=source, level=level)


seed_demo_activity()

def activity_list(limit: int = 50) -> List[Dict[str, Any]]:
    with ACTIVITY_LOCK:
        items = list(ACTIVITY_EVENTS)
    items.reverse()
    return items[: max(1, min(limit, ACTIVITY_MAX))]


def workspace_diff(path: str = "") -> Dict[str, Any]:
    """Readonly unified diff snapshot for a path (or all)."""
    cleaned = (path or "").strip().lstrip("./")
    if cleaned:
        body = MOCK_DIFFS.get(cleaned)
        if body is None:
            return {"path": cleaned, "diff": "", "note": "no changes"}
        return {"path": cleaned, "diff": body, "note": "mock unified diff"}
    files = [{"path": k, "has_diff": True} for k in MOCK_DIFFS]
    return {"files": files, "note": "mock diff index"}



_LOG_SECRET = re.compile(r"(token=|bearer\s+)[^&\s\"']+", re.IGNORECASE)


def log(msg: str) -> None:
    # Request lines may carry ?token=...; never echo secrets to stdout logs.
    print(f"[mock-host] {_LOG_SECRET.sub(lambda m: m.group(1) + '[redacted]', msg)}", flush=True)


def json_bytes(obj: Any) -> bytes:
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")


# ---------- WebSocket helpers ----------

def _ws_accept_key(key: str) -> str:
    guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    digest = hashlib.sha1((key + guid).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def _recv_exact(conn: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("closed")
        buf += chunk
    return buf


def ws_recv_text(conn: socket.socket) -> str:
    hdr = _recv_exact(conn, 2)
    b1, b2 = hdr[0], hdr[1]
    opcode = b1 & 0x0F
    masked = (b2 & 0x80) != 0
    ln = b2 & 0x7F
    if ln == 126:
        ln = struct.unpack("!H", _recv_exact(conn, 2))[0]
    elif ln == 127:
        ln = struct.unpack("!Q", _recv_exact(conn, 8))[0]
    mask = _recv_exact(conn, 4) if masked else b""
    payload = _recv_exact(conn, ln)
    if masked:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    if opcode == 0x8:
        raise ConnectionError("client close")
    if opcode == 0x9:
        ws_send_frame(conn, 0xA, payload)
        return ws_recv_text(conn)
    if opcode != 0x1:
        return ws_recv_text(conn)
    return payload.decode("utf-8")


def ws_send_frame(conn: socket.socket, opcode: int, payload: bytes) -> None:
    header = bytearray([0x80 | opcode])
    ln = len(payload)
    if ln < 126:
        header.append(ln)
    elif ln < (1 << 16):
        header.append(126)
        header.extend(struct.pack("!H", ln))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", ln))
    conn.sendall(header + payload)


def ws_send_text(conn: socket.socket, text: str) -> None:
    ws_send_frame(conn, 0x1, text.encode("utf-8"))


def token_matches(presented: Optional[str], expected: str) -> bool:
    """Constant-time compare that also fails closed for non-ASCII input."""
    if not isinstance(presented, str) or not expected:
        return False
    return hmac.compare_digest(
        presented.encode("utf-8", "surrogatepass"),
        expected.encode("utf-8", "surrogatepass"),
    )


def extract_token(headers: Dict[str, str], query: Dict[str, List[str]]) -> Optional[str]:
    auth = headers.get("authorization") or headers.get("Authorization")
    if auth and auth.lower().startswith("bearer "):
        return auth[7:].strip()
    xt = headers.get("x-bridge-token") or headers.get("X-Bridge-Token")
    if xt:
        return xt.strip()
    if "token" in query and query["token"]:
        return query["token"][0]
    return None


def handle_bridge_client(conn: socket.socket, addr: Tuple[str, int]) -> None:
    conn.settimeout(120)
    try:
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                return
            data += chunk
        header_blob, _ = data.split(b"\r\n\r\n", 1)
        lines = header_blob.decode("latin1", errors="replace").split("\r\n")
        req = lines[0]
        method, path, _ = req.split(" ", 2)
        headers: Dict[str, str] = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        parsed = urlparse(path)
        query = parse_qs(parsed.query)

        if method != "GET" or parsed.path != "/bridge/ws":
            body = b"not found"
            conn.sendall(
                b"HTTP/1.1 404 Not Found\r\nContent-Length: "
                + str(len(body)).encode()
                + b"\r\nConnection: close\r\n\r\n"
                + body
            )
            return

        token = extract_token(headers, query)
        if not token_matches(token, BRIDGE_TOKEN):
            body = b"unauthorized"
            conn.sendall(
                b"HTTP/1.1 401 Unauthorized\r\nContent-Length: "
                + str(len(body)).encode()
                + b"\r\nConnection: close\r\n\r\n"
                + body
            )
            return

        key = headers.get("sec-websocket-key")
        if not key:
            conn.sendall(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
            return
        accept = _ws_accept_key(key)
        conn.sendall(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n"
                "\r\n"
            ).encode("ascii")
        )
        log(f"bridge connected from {addr}")

        registered = False
        platform = "unknown"

        while True:
            raw = ws_recv_text(conn)
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                ws_send_text(conn, json.dumps({"type": "error", "error": "invalid json"}))
                continue
            mtype = msg.get("type")

            if mtype == "ping":
                ws_send_text(conn, json.dumps({"type": "pong", "ts": msg.get("ts")}))
                continue

            if mtype == "register":
                platform = msg.get("platform") or "unknown"
                registered = True
                ws_send_text(conn, json.dumps({"type": "register_ack", "ok": True, "error": ""}))
                log(f"registered platform={platform}")
                continue

            if not registered:
                ws_send_text(
                    conn,
                    json.dumps({"type": "register_ack", "ok": False, "error": "send register first"}),
                )
                continue

            if mtype == "card_action":
                _handle_card_action(conn, msg)
                continue

            if mtype == "cancel":
                _handle_cancel(conn, msg)
                continue

            if mtype == "message":
                _handle_message(conn, msg)
                continue

            if mtype == "terminal_open":
                sk_o = msg.get("session_key") or ""
                stream_o = msg.get("stream_id") or f"term-{uuid.uuid4().hex[:8]}"
                st_o = _session_state(sk_o)
                st_o["terminal_stream_id"] = stream_o
                st_o["term_cols"] = max(20, min(240, int(msg.get("cols") or 80)))
                st_o["term_rows"] = max(5, min(120, int(msg.get("rows") or 24)))
                ws_send_text(conn, json.dumps({
                    "type": "terminal_open_ack", "ok": True,
                    "session_key": sk_o, "stream_id": stream_o,
                    "cols": st_o["term_cols"], "rows": st_o["term_rows"],
                }))
                continue

            if mtype == "terminal_close":
                sk_c = msg.get("session_key") or ""
                stream_c = msg.get("stream_id") or ""
                st_c = _session_state(sk_c)
                active_c = st_c.get("terminal_stream_id")
                if not stream_c or not active_c or stream_c == active_c:
                    st_c.pop("terminal_stream_id", None)
                    pty_mgr_c = _get_pty_manager()
                    if pty_mgr_c is not None:
                        pty_mgr_c.close(sk_c)
                    ws_send_text(conn, json.dumps({
                        "type": "terminal_exit", "session_key": sk_c,
                        "stream_id": stream_c or active_c or "", "exit_code": 0,
                    }))
                continue

            if mtype == "terminal_input":
                _handle_terminal_input(conn, msg)
                continue

            if mtype == "terminal_resize":
                # store geometry for demo; Host real PTY would apply ioctl
                sk_r = msg.get("session_key") or ""
                st_r = _session_state(sk_r)
                try:
                    st_r["term_cols"] = int(msg.get("cols") or st_r.get("term_cols") or 80)
                except (TypeError, ValueError):
                    st_r["term_cols"] = 80
                try:
                    st_r["term_rows"] = int(msg.get("rows") or st_r.get("term_rows") or 24)
                except (TypeError, ValueError):
                    st_r["term_rows"] = 24
                # Apply resize to real PTY if active
                pty_mgr_r = _get_pty_manager()
                if pty_mgr_r is not None:
                    pty_mgr_r.resize(sk_r, st_r["term_cols"], st_r["term_rows"])
                ws_send_text(
                    conn,
                    json.dumps(
                        {
                            "type": "terminal_ack",
                            "session_key": sk_r,
                            "cols": st_r["term_cols"],
                            "rows": st_r["term_rows"],
                            "stream_id": msg.get("stream_id") or st_r.get("terminal_stream_id") or "",
                        }
                    ),
                )
                continue

            ws_send_text(
                conn,
                json.dumps(
                    {
                        "type": "reply",
                        "session_key": msg.get("session_key"),
                        "reply_ctx": msg.get("reply_ctx"),
                        "content": f"mock: unknown type {mtype}",
                        "format": "text",
                    }
                ),
            )
    except ConnectionError:
        log(f"bridge disconnected {addr}")
    except Exception:
        log(f"bridge error:\n{traceback.format_exc()}")
    finally:
        try:
            conn.close()
        except OSError:
            pass



class RealPtyManager:
    """Manages real PTY processes per session key.

    When HUAN_REAL_PTY=1, spawns a real shell with PTY and pipes I/O
    through the Bridge WebSocket terminal channel.
    """

    def __init__(self) -> None:
        self._ptys: Dict[str, Dict[str, Any]] = {}

    def get_or_spawn(self, sk: str, cols: int = 80, rows: int = 24) -> Dict[str, Any]:
        """Get existing PTY or spawn a new shell for session key."""
        if sk in self._ptys:
            p = self._ptys[sk]
            if p["proc"].poll() is None:
                return p
            # Process died, clean up
            self._close(sk)

        shell = os.environ.get("SHELL", "/bin/bash")
        master_fd, slave_fd = pty.openpty()

        # Set initial window size
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

        proc = subprocess.Popen(
            [shell, "-l"],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            preexec_fn=os.setsid,
            env={**os.environ, "TERM": "xterm-256color", "COLUMNS": str(cols), "LINES": str(rows)},
        )
        os.close(slave_fd)

        # Set non-blocking
        import fcntl as f
        flags = fcntl.fcntl(master_fd, f.F_GETFL)
        fcntl.fcntl(master_fd, f.F_SETFL, flags | os.O_NONBLOCK)

        self._ptys[sk] = {
            "master_fd": master_fd,
            "proc": proc,
            "cols": cols,
            "rows": rows,
        }
        return self._ptys[sk]

    def write(self, sk: str, data: str) -> None:
        """Write data to PTY stdin."""
        p = self._ptys.get(sk)
        if p and p["proc"].poll() is None:
            try:
                os.write(p["master_fd"], data.encode("utf-8", errors="replace"))
            except OSError:
                self._close(sk)

    def read(self, sk: str, timeout: float = 0.05) -> str:
        """Read available data from PTY stdout (non-blocking)."""
        p = self._ptys.get(sk)
        if not p or p["proc"].poll() is not None:
            return ""
        chunks = []
        try:
            while True:
                r, _, _ = select.select([p["master_fd"]], [], [], timeout)
                if not r:
                    break
                chunk = os.read(p["master_fd"], 65536)
                if not chunk:
                    break
                chunks.append(chunk.decode("utf-8", errors="replace"))
                timeout = 0.01  # Shorter timeout for subsequent reads
        except OSError:
            pass
        return "".join(chunks)

    def resize(self, sk: str, cols: int, rows: int) -> None:
        """Resize PTY window."""
        p = self._ptys.get(sk)
        if p and p["proc"].poll() is not None:
            return
        if p:
            try:
                winsize = struct.pack("HHHH", rows, cols, 0, 0)
                fcntl.ioctl(p["master_fd"], termios.TIOCSWINSZ, winsize)
                p["cols"] = cols
                p["rows"] = rows
            except OSError:
                pass

    def is_alive(self, sk: str) -> bool:
        """Check if PTY process is still running."""
        p = self._ptys.get(sk)
        return p is not None and p["proc"].poll() is None

    def _close(self, sk: str) -> None:
        """Close PTY for a session."""
        p = self._ptys.pop(sk, None)
        if p:
            try:
                os.close(p["master_fd"])
            except OSError:
                pass
            try:
                p["proc"].terminate()
            except OSError:
                pass

    def close(self, sk: str) -> None:
        self._close(sk)

    def cleanup_all(self) -> None:
        """Close all PTY processes."""
        for sk in list(self._ptys.keys()):
            self._close(sk)


# Global PTY manager (initialized when HUAN_REAL_PTY=1)
_pty_manager: Optional["RealPtyManager"] = None

def _get_pty_manager() -> Optional["RealPtyManager"]:
    global _pty_manager
    if os.environ.get("HUAN_REAL_PTY") == "1" and _pty_manager is None:
        _pty_manager = RealPtyManager()
    return _pty_manager


def _handle_terminal_input(conn: socket.socket, msg: Dict[str, Any]) -> None:
    """Lightweight terminal channel over Bridge (not a full PTY).

    Host-side real shells would spawn PTY; Mock echoes + fake command results.
    When HUAN_REAL_PTY=1, uses real PTY instead of mock.
    """
    sk = msg.get("session_key") or ""
    data = (msg.get("data") or msg.get("content") or "").rstrip("\r\n")
    stream_id = msg.get("stream_id") or f"term-{uuid.uuid4().hex[:8]}"
    st_stream = _session_state(sk)
    active_stream = st_stream.get("terminal_stream_id")
    if active_stream and stream_id != active_stream:
        ws_send_text(conn, json.dumps({
            "type": "terminal_out", "session_key": sk, "stream_id": stream_id,
            "data": "", "done": True, "exit_code": 409, "error": "stale terminal stream",
        }))
        return

    def out(chunk: str, *, done: bool = False, exit_code: Optional[int] = None) -> None:
        payload: Dict[str, Any] = {
            "type": "terminal_out",
            "session_key": sk,
            "stream_id": stream_id,
            "data": chunk,
        }
        if done:
            payload["done"] = True
        if exit_code is not None:
            payload["exit_code"] = exit_code
        ws_send_text(conn, json.dumps(payload))

    if not data:
        out("", done=True, exit_code=0)
        return

    # Real PTY mode: pipe to actual shell
    pty_mgr = _get_pty_manager()
    if pty_mgr is not None:
        st = _session_state(sk)
        cols = int(st.get("term_cols") or 80)
        rows = int(st.get("term_rows") or 24)
        pty_mgr.get_or_spawn(sk, cols=cols, rows=rows)
        pty_mgr.write(sk, data + "\n")
        # Read output with a small delay to let the shell process
        # (module-level `time` — do not re-import here or it shadows date/handlers)
        time.sleep(0.1)
        output = pty_mgr.read(sk, timeout=0.2)
        if output:
            out(output)
        done_flag = not pty_mgr.is_alive(sk)
        out("", done=done_flag, exit_code=0 if not done_flag else None)
        return

    lower = data.strip().lower()
    # local echo (skip raw ctrl chars)
    if data != "\x03":
        out(f"$ {data}\n")

    # Ctrl-C / soft interrupt
    if data == "\x03" or lower in {"^c", "ctrl-c", "ctrl+c"}:
        out("^C\n", done=True, exit_code=130)
        return
    if lower in {"y", "n", "yes", "no"}:
        out(f"(ack) {data.strip()}\n", done=True, exit_code=0)
        return
    if lower in {"help", "?"}:
        st_h = _session_state(sk)
        cols_h = st_h.get("term_cols") or 80
        rows_h = st_h.get("term_rows") or 24
        out(
            "HuanHermes Mock terminal (Bridge terminal_input).\n"
            f"Commands: {mock_term_help_commands()}\n"
            f"Geometry: {cols_h}x{rows_h} (from terminal_resize)\n"
            "Quick interrupt: Ctrl-C (^C)\n"
            "This is protocol demo only — not a real remote shell.\n",
            done=True,
            exit_code=0,
        )
        return
    if lower.startswith("/perm"):
        # Mock permission request: sends a card with Allow/Deny buttons
        tool_name = data.strip().split(maxsplit=1)[1] if len(data.strip().split()) > 1 else "file_write"
        card_msg = {
            "type": "card",
            "session_key": sk,
            "stream_id": stream_id,
            "text": (
                f"Agent requests permission to use tool: {tool_name}\n\n"
                f"Details: The agent wants to {tool_name} a file. This is a mock permission request."
            ),
            "buttons": [
                {"text": "Allow", "data": "allow"},
                {"text": "Allow all", "data": "allow_all"},
                {"text": "Deny", "data": "deny"},
            ],
        }
        ws_send_text(conn, json.dumps(card_msg))
        out(f"Permission request sent for tool: {tool_name}\n", done=True, exit_code=0)
        return

    # ── Phase D: table-driven registry (simple demos) ──
    # Complex workspace/session commands fall through to the chain below.
    _reg_hit = mock_term_dispatch(data, lower)
    if _reg_hit is not None:
        _body, _code = _reg_hit
        out(_body, done=True, exit_code=_code)
        return

    if lower == "pwd":
        st = _session_state(sk)
        out((st.get("workdir") or "/workspace") + "\n", done=True, exit_code=0)
    elif lower == "cd" or lower.startswith("cd "):
        st = _session_state(sk)
        cur = st.get("workdir") or "/workspace"
        arg = data.strip()[2:].strip() if lower.startswith("cd") else ""
        if not arg or arg == "~":
            target = "/workspace"
        elif arg == "-":
            target = st.get("prev_workdir") or "/workspace"
        elif arg.startswith("/"):
            target = arg.rstrip("/") or "/"
            if not target.startswith("/workspace"):
                # allow absolute under /workspace only
                if target == "/":
                    target = "/workspace"
                else:
                    out(f"cd: {arg}: permission denied (mock stays under /workspace)\n", done=True, exit_code=1)
                    return
        else:
            # relative
            base = cur.rstrip("/")
            parts = [p for p in (base + "/" + arg).split("/") if p and p != "."]
            stack = []
            for p in parts:
                if p == "..":
                    if stack:
                        stack.pop()
                else:
                    stack.append(p)
            target = "/" + "/".join(stack) if stack else "/workspace"
            if not target.startswith("/workspace"):
                target = "/workspace"
        rel = target.replace("/workspace", "").lstrip("/")
        node, cleaned = _ws_resolve(rel)
        if target != "/workspace" and (node is None or node.get("type") != "dir"):
            out(f"cd: {arg}: No such directory\n", done=True, exit_code=1)
        else:
            st["prev_workdir"] = cur
            st["workdir"] = target if target.startswith("/workspace") else "/workspace"
            if target == "/workspace" or (node and node.get("type") == "dir"):
                if target != "/workspace" and cleaned:
                    st["workdir"] = "/workspace/" + cleaned
                out("", done=True, exit_code=0)
            else:
                out(f"cd: {arg}: No such directory\n", done=True, exit_code=1)
    elif lower.startswith("mkdir ") or lower == "mkdir":
        # mock mkdir: mkdir DIR... or mkdir -p DIR; strip short -p/-m flags; need ≥1 DIR else 1; silent 0 (do NOT mutate WORKSPACE_TREE)
        parts = data.strip().split()
        tokens = parts[1:]
        dirs = []
        i = 0
        while i < len(tokens):
            t = tokens[i]
            if t in ("-p", "--parents"):
                i += 1
                continue
            if t == "-m":
                i += 2  # skip mode value
                continue
            if t.startswith("-m") and len(t) > 2:
                i += 1
                continue
            if t.startswith("-") and t != "-":
                i += 1
                continue
            dirs.append(t)
            i += 1
        if not dirs:
            out("mkdir: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower in {"ls", "ls -la"} or lower.startswith("ls "):
        st_ls = _session_state(sk)
        rel = (st_ls.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
        node, _ = _ws_resolve(rel)
        if node is None or node.get("type") == "file":
            out("ls: cannot access workdir\n", done=True, exit_code=1)
        else:
            kids = node.get("children") or {}
            names = []
            for name, child in sorted(kids.items(), key=lambda x: (x[1].get("type") != "dir", x[0])):
                names.append(name + ("/" if child.get("type") == "dir" else ""))
            out(("\n".join(names) + ("\n" if names else "")), done=True, exit_code=0)
    elif lower == "whoami":
        out("huanhermes-mock\n", done=True, exit_code=0)
    elif lower.startswith("which "):
        name = data.strip()[6:].strip()
        known = MOCK_TERM_KNOWN
        if name in known:
            out(f"/usr/bin/{name}\n", done=True, exit_code=0)
        else:
            out(f"which: no {name} in mock PATH\n", done=True, exit_code=1)
    elif lower in {"clear", "cls"}:
        out("\x1b[2J\x1b[H[mock-clear]\n", done=True, exit_code=0)
    elif lower.startswith("uname ") or lower == "uname":
        # mock uname: fixed Linux demo (not real kernel)
        parts = data.strip().split()
        flag = parts[1] if len(parts) > 1 else ""
        if flag in {"-a", "--all"}:
            out("Linux mock-host 6.1.0-mock #1 SMP x86_64 GNU/Linux\n", done=True, exit_code=0)
        elif flag == "-n":
            out("mock-host\n", done=True, exit_code=0)
        elif flag == "-r":
            out("6.1.0-mock\n", done=True, exit_code=0)
        else:
            # bare, -s, or other → Linux
            out("Linux\n", done=True, exit_code=0)
    elif lower.startswith("hostname ") or lower == "hostname":
        # mock hostname: fixed demo host
        parts = data.strip().split()
        flag = parts[1] if len(parts) > 1 else ""
        if flag in {"-f", "--fqdn"}:
            out("mock-host.local\n", done=True, exit_code=0)
        else:
            out("mock-host\n", done=True, exit_code=0)
    elif lower.startswith("id ") or lower == "id":
        # mock id: fixed uid/gid/user demo
        parts = data.strip().split()
        flags = set(parts[1:])
        if "-un" in flags or flags == {"-u", "-n"} or flags == {"-n", "-u"}:
            out("mock\n", done=True, exit_code=0)
        elif "-u" in flags:
            out("1000\n", done=True, exit_code=0)
        elif "-g" in flags:
            out("1000\n", done=True, exit_code=0)
        else:
            out("uid=1000(mock) gid=1000(mock) groups=1000(mock)\n", done=True, exit_code=0)
    elif lower.startswith("cat ") or lower.startswith("head ") or lower.startswith("tail ") or lower.startswith("wc "):
        st_c = _session_state(sk)
        parts = data.strip().split()
        cmd = parts[0].lower() if parts else "cat"
        n_lines = 10
        arg_tokens = parts[1:] if len(parts) > 1 else []
        path_bits = []
        i = 0
        while i < len(arg_tokens):
            t = arg_tokens[i]
            if t in {"-n", "--lines"} and i + 1 < len(arg_tokens):
                try:
                    n_lines = max(1, min(500, int(arg_tokens[i + 1])))
                except Exception:
                    pass
                i += 2
                continue
            if t.startswith("-n") and len(t) > 2 and t[2:].isdigit():
                n_lines = max(1, min(500, int(t[2:])))
                i += 1
                continue
            if t.startswith("-") and t not in {"-"}:
                i += 1
                continue
            path_bits.append(t)
            i += 1
        arg = " ".join(path_bits)
        path = arg or "(empty)"
        wd = st_c.get("workdir") or "/workspace"
        # resolve relative to workdir
        if path.startswith("/"):
            rel = path.replace("/workspace", "").lstrip("/")
        else:
            base = wd.replace("/workspace", "").lstrip("/")
            rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
        node, cleaned = _ws_resolve(rel)
        if node is None or node.get("type") != "file":
            out(f"{cmd}: {path}: No such file\n", done=True, exit_code=1)
        else:
            content = node.get("content") or ""
            if cmd == "wc":
                lines = content.count("\n") + (0 if content.endswith("\n") or not content else 1)
                words = len(content.split())
                out(f"{lines} {words} {len(content)} {cleaned or path}\n", done=True, exit_code=0)
            elif cmd == "head":
                out("\n".join(content.splitlines()[:n_lines]) + ("\n" if content else ""), done=True, exit_code=0)
            elif cmd == "tail":
                out("\n".join(content.splitlines()[-n_lines:]) + ("\n" if content else ""), done=True, exit_code=0)
            else:
                out(content if content.endswith("\n") or not content else content + "\n", done=True, exit_code=0)
    elif lower == "date" or lower.startswith("date ") or lower.startswith("date+"):
        # Limited date formats (mock): default ISO; supports -u and +FMT subset
        use_utc = "-u" in lower.split() or lower.startswith("date -u")
        fmt = None
        raw = data.strip()
        if "+" in raw:
            fmt = raw[raw.index("+") + 1 :].strip()
        tstruct = time.gmtime() if use_utc else time.localtime()
        if not fmt:
            out(time.strftime("%Y-%m-%dT%H:%M:%SZ" if use_utc else "%Y-%m-%d %H:%M:%S %z", tstruct) + "\n", done=True, exit_code=0)
        else:
            # map common tokens
            mapping = {
                "%Y": "%Y", "%m": "%m", "%d": "%d", "%H": "%H", "%M": "%M", "%S": "%S",
                "%F": "%Y-%m-%d", "%T": "%H:%M:%S", "%s": str(int(time.time())),
            }
            out_s = fmt
            if "%s" in out_s:
                out_s = out_s.replace("%s", str(int(time.mktime(tstruct)) if not use_utc else int(time.time())))
            try:
                # convert remaining via strftime if looks like strftime
                py_fmt = out_s
                for k in ("%F", "%T", "%Y", "%m", "%d", "%H", "%M", "%S"):
                    pass
                rendered = time.strftime(py_fmt.replace("%F", "%Y-%m-%d").replace("%T", "%H:%M:%S"), tstruct)
                out(rendered + "\n", done=True, exit_code=0)
            except Exception:
                out(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n", done=True, exit_code=0)
    elif lower == "env":
        st_e = _session_state(sk)
        lines = [
            "TERM=huanhermes-mock",
            "USER=huanhermes-mock",
            f"PWD={st_e.get('workdir') or '/workspace'}",
            f"COLUMNS={st_e.get('term_cols') or 80}",
            f"LINES={st_e.get('term_rows') or 24}",
            f"HH_SESSION={sk}",
        ]
        extra = st_e.get("env") if isinstance(st_e.get("env"), dict) else {}
        for k in sorted(extra.keys()):
            lines.append(f"{k}={extra[k]}")
        out("\n".join(lines) + "\n", done=True, exit_code=0)
    elif lower.startswith("stty ") or lower == "stty" or lower in {"tty size", "size"}:
        # mock stty: fixed baud/geometry demo (not real PTY/ioctl)
        out("speed 38400 baud; rows 24; columns 80; line = 0;\n", done=True, exit_code=0)

    elif lower in {"tree", "tree -L 2", "tree -L 3"} or lower.startswith("tree "):
        st_t = _session_state(sk)
        rel = (st_t.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
        node, _ = _ws_resolve(rel)
        if node is None or node.get("type") != "dir":
            out("tree: invalid workdir\n", done=True, exit_code=1)
        else:
            lines = ["."]
            def walk(n, prefix=""):
                kids = n.get("children") or {}
                items = sorted(kids.items(), key=lambda x: (x[1].get("type") != "dir", x[0]))
                for idx, (name, child) in enumerate(items):
                    last = idx == len(items) - 1
                    branch = "└── " if last else "├── "
                    lines.append(prefix + branch + name + ("/" if child.get("type") == "dir" else ""))
                    if child.get("type") == "dir" and len(prefix) < 12:
                        walk(child, prefix + ("    " if last else "│   "))
            walk(node)
            out("\n".join(lines) + "\n", done=True, exit_code=0)
    elif lower in {"df", "df -h"}:
        out(
            "Filesystem      Size  Used Avail Use% Mounted on\n"
            "mockfs           8.0G  1.2G  6.8G  15% /workspace\n",
            done=True,
            exit_code=0,
        )
    elif lower in {"free", "free -h", "free -m"}:
        out(
            "              total        used        free\n"
            "Mem:           5.8G        2.1G        3.7G\n"
            "Swap:            0B          0B          0B\n",
            done=True,
            exit_code=0,
        )
    elif lower in {"ps", "ps aux", "ps -ef"}:
        out(
            "PID TTY          TIME CMD\n"
            "  1 ?        00:00:01 mock-host\n"
            " 42 ?        00:00:00 bridge-ws\n"
            " 43 ?        00:00:00 mgmt-http\n",
            done=True,
            exit_code=0,
        )
    elif lower in {"uptime"}:
        out(" 12:00:00 up 3 days,  4:12,  1 user,  load average: 0.12, 0.08, 0.05\n", done=True, exit_code=0)


    elif (
        lower.startswith("basename ")
        or lower.startswith("dirname ")
        or lower.startswith("realpath ")
        or lower == "realpath"
    ):
        parts = data.strip().split(None, 1)
        cmd = parts[0].lower() if parts else ""
        arg = parts[1].strip() if len(parts) > 1 else ""
        st_p = _session_state(sk)
        wd = st_p.get("workdir") or "/workspace"
        if not arg:
            out(f"{cmd}: missing operand\n", done=True, exit_code=1)
        elif cmd == "realpath":
            # mock realpath: absolute as-is; relative → /workspace/PATH (strip ./)
            if arg.startswith("/"):
                out(arg + "\n", done=True, exit_code=0)
            else:
                p = arg
                while p.startswith("./"):
                    p = p[2:]
                out("/workspace/" + p + "\n", done=True, exit_code=0)
        else:
            if arg.startswith("/"):
                path = arg
            else:
                path = (wd.rstrip("/") + "/" + arg).replace("//", "/")
            # normalize ..
            segs = []
            for p in path.split("/"):
                if not p or p == ".":
                    continue
                if p == "..":
                    if segs:
                        segs.pop()
                else:
                    segs.append(p)
            norm = "/" + "/".join(segs) if segs else "/"
            if cmd == "basename":
                out((segs[-1] if segs else "/") + "\n", done=True, exit_code=0)
            else:
                # dirname
                out(("/" + "/".join(segs[:-1]) if len(segs) > 1 else "/") + "\n", done=True, exit_code=0)
    elif lower.startswith("stat ") or lower == "stat":
        st_s = _session_state(sk)
        arg = data.strip()[4:].strip() if lower.startswith("stat") else ""
        if not arg:
            out("stat: missing operand\n", done=True, exit_code=1)
        else:
            wd = st_s.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None:
                out(f"stat: cannot stat '{arg}': No such file or directory\n", done=True, exit_code=1)
            else:
                typ = node.get("type") or "?"
                size = node.get("size")
                if size is None and typ == "file":
                    size = len(node.get("content") or "")
                if size is None:
                    size = 0
                out(
                    f"  File: {cleaned or arg}\n"
                    f"  Type: {typ}\n"
                    f"  Size: {size}\n"
                    f"  Mock: readonly workspace node\n",
                    done=True,
                    exit_code=0,
                )
    elif lower in {"du", "du -h", "du -sh", "du -s"} or lower.startswith("du "):
        st_d = _session_state(sk)
        rel = (st_d.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
        node, cleaned = _ws_resolve(rel)

        def du_size(n):
            if not n:
                return 0
            if n.get("type") == "file":
                return int(n.get("size") or len(n.get("content") or "") or 0)
            total = 0
            for child in (n.get("children") or {}).values():
                total += du_size(child)
            return total

        sz = du_size(node)
        label = cleaned or "."
        out(f"{sz}\t{label}\n", done=True, exit_code=0)


    elif lower in {"true", ":", "true -"}:
        out("", done=True, exit_code=0)
    elif lower in {"false"}:
        out("", done=True, exit_code=1)
    elif lower.startswith("printf ") or lower == "printf":
        # mock printf: FORMAT [ARGS...]; need FORMAT else 1; basic %s / %% / \n
        parts = data.strip().split()
        if len(parts) < 2:
            out("printf: missing operand\n", done=True, exit_code=1)
        else:
            fmt = parts[1]
            if (fmt.startswith('"') and fmt.endswith('"')) or (fmt.startswith("'") and fmt.endswith("'")):
                fmt = fmt[1:-1]
            args = parts[2:]
            cleaned_args = []
            for a in args:
                if (a.startswith('"') and a.endswith('"')) or (a.startswith("'") and a.endswith("'")):
                    cleaned_args.append(a[1:-1])
                else:
                    cleaned_args.append(a)
            out_s = fmt.replace("\\n", "\n")
            out_s = out_s.replace("%%", "\0")
            if "%s" in out_s:
                repl = cleaned_args[0] if cleaned_args else ""
                out_s = out_s.replace("%s", repl, 1)
            out_s = out_s.replace("\0", "%")
            # no-% formats: ensure trailing newline if not already present
            if "%" not in fmt.replace("%%", "") and not out_s.endswith("\n"):
                out_s = out_s + "\n"
            out(out_s, done=True, exit_code=0)


    elif lower.startswith("sleep "):
        # Non-blocking mock: report intent only (no real delay — keeps Bridge responsive)
        arg = data.strip()[6:].strip() or "0"
        out(f"[mock-sleep] skipped ({arg}s) — mock does not block\n", done=True, exit_code=0)
    elif lower.startswith("touch ") or lower == "touch":
        # mock touch: need ≥1 FILE else 1; silent 0 (do NOT mutate WORKSPACE_TREE)
        parts = data.strip().split()
        if len(parts) < 2:
            out("touch: missing file operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("history ") or lower == "history":
        args = data.strip().split()[1:] if lower.startswith("history ") else []
        if args:
            # history -c or any args: empty output, exit 0
            out("", done=True, exit_code=0)
        else:
            out(
                "    1  ls\n"
                "    2  cd /home\n"
                "    3  cat README.md\n"
                "    4  pwd\n"
                "    5  history\n",
                done=True,
                exit_code=0,
            )


    elif lower.startswith("grep ") or lower.startswith("grep -"):
        # Minimal: grep <pattern> [path] over workspace file contents (mock)
        parts = data.strip().split()
        # drop flags like -n -i -r for mock simplicity but honor -i
        flags = {p for p in parts[1:] if p.startswith("-")}
        args = [p for p in parts[1:] if not p.startswith("-")]
        if not args:
            out("grep: missing pattern\n", done=True, exit_code=2)
        else:
            pattern = args[0]
            path_arg = args[1] if len(args) > 1 else ""
            st_g = _session_state(sk)
            wd = st_g.get("workdir") or "/workspace"
            if path_arg:
                if path_arg.startswith("/"):
                    rel = path_arg.replace("/workspace", "").lstrip("/")
                else:
                    base = wd.replace("/workspace", "").lstrip("/")
                    rel = "/".join(p for p in (base + "/" + path_arg).split("/") if p and p != ".")
            else:
                rel = wd.replace("/workspace", "").lstrip("/")
            node, cleaned = _ws_resolve(rel)
            if node is None:
                out(f"grep: {path_arg or rel}: No such file or directory\n", done=True, exit_code=2)
            else:
                files = _ws_walk_files(node, cleaned)
                if node.get("type") == "file":
                    files = [(cleaned, node)]
                ignore_case = any(f in {"-i", "--ignore-case"} for f in flags) or "-i" in lower
                lines_out = []
                try:
                    import re as _re
                    rx = _re.compile(pattern, _re.I if ignore_case else 0)
                except Exception:
                    rx = None
                for fpath, fnode in files:
                    content = fnode.get("content") or ""
                    for i, line in enumerate(content.splitlines(), 1):
                        hit = False
                        if rx is not None:
                            hit = rx.search(line) is not None
                        else:
                            hay = line.lower() if ignore_case else line
                            needle = pattern.lower() if ignore_case else pattern
                            hit = needle in hay
                        if hit:
                            lines_out.append(f"{fpath}:{i}:{line}")
                if not lines_out:
                    out("", done=True, exit_code=1)
                else:
                    out("\n".join(lines_out[:200]) + "\n", done=True, exit_code=0)
    elif lower.startswith("find ") or lower == "find" or lower.startswith("find ."):
        parts = data.strip().split()
        path_arg = "."
        name_pat = None
        type_f = None
        i = 1
        while i < len(parts):
            p = parts[i]
            if p == "-name" and i + 1 < len(parts):
                name_pat = parts[i + 1].strip("'\"")
                i += 2
                continue
            if p == "-type" and i + 1 < len(parts):
                type_f = parts[i + 1]
                i += 2
                continue
            if not p.startswith("-") and path_arg == ".":
                path_arg = p
            i += 1
        st_f = _session_state(sk)
        wd = st_f.get("workdir") or "/workspace"
        if path_arg in {".", "./"}:
            rel = wd.replace("/workspace", "").lstrip("/")
        elif path_arg.startswith("/"):
            rel = path_arg.replace("/workspace", "").lstrip("/")
        else:
            base = wd.replace("/workspace", "").lstrip("/")
            rel = "/".join(p for p in (base + "/" + path_arg).split("/") if p and p != ".")
        node, cleaned = _ws_resolve(rel)
        if node is None:
            out(f"find: '{path_arg}': No such file or directory\n", done=True, exit_code=1)
        else:
            results = []

            def walk(n, prefix):
                if not n:
                    return
                typ = n.get("type")
                if typ == "file":
                    if type_f in (None, "f"):
                        base = prefix.split("/")[-1] if prefix else ""
                        if name_pat is None or _fnmatch(base, name_pat):
                            results.append(prefix or ".")
                    return
                # dir
                if type_f in (None, "d") and prefix:
                    base = prefix.split("/")[-1]
                    if name_pat is None or _fnmatch(base, name_pat):
                        if type_f == "d" or name_pat:
                            results.append(prefix)
                kids = n.get("children") or {}
                for name, child in sorted(kids.items()):
                    p = f"{prefix}/{name}" if prefix else name
                    walk(child, p)

            def _fnmatch(name, pat):
                import fnmatch
                return fnmatch.fnmatch(name, pat)

            walk(node, cleaned)
            if not results and node.get("type") != "file":
                # always list files if no filter
                for fpath, _ in _ws_walk_files(node, cleaned):
                    if name_pat is None or _fnmatch(fpath.split("/")[-1], name_pat):
                        if type_f in (None, "f"):
                            results.append(fpath)
            out(("\n".join(results[:200]) + ("\n" if results else "")), done=True, exit_code=0)
    elif lower.startswith("seq ") or lower == "seq":
        # mock seq: seq LAST | seq FIRST LAST | seq FIRST INCR LAST; cap 20 lines; missing/non-int → 1
        parts = data.strip().split()
        try:
            if len(parts) == 1:
                raise ValueError("missing")
            if len(parts) == 2:
                start, step, end = 1, 1, int(parts[1])
            elif len(parts) == 3:
                start, step, end = int(parts[1]), 1, int(parts[2])
            elif len(parts) >= 4:
                start, step, end = int(parts[1]), int(parts[2]), int(parts[3])
            else:
                raise ValueError("args")
            if step == 0:
                raise ValueError("step")
            vals = []
            x = start
            if step > 0:
                while x <= end and len(vals) < 20:
                    vals.append(str(x))
                    x += step
            else:
                while x >= end and len(vals) < 20:
                    vals.append(str(x))
                    x += step
            out("\n".join(vals) + ("\n" if vals else ""), done=True, exit_code=0)
        except Exception:
            out("seq: invalid arguments\n", done=True, exit_code=1)


    elif lower.startswith("sort") or lower == "sort":
        # sort lines from stdin not available — sort mock list args or help
        args = data.strip().split(None, 1)
        payload = args[1] if len(args) > 1 else ""
        if not payload:
            out("sort: (mock) pass space-separated tokens to sort\n", done=True, exit_code=0)
        else:
            # if multiline use lines else tokens
            if "\n" in payload:
                lines = payload.splitlines()
            else:
                lines = payload.split()
            reverse = "-r" in lower
            lines = sorted(lines, reverse=reverse)
            out("\n".join(lines) + ("\n" if lines else ""), done=True, exit_code=0)
    elif lower.startswith("export "):
        # mock env set — session-local only
        assign = data.strip()[7:].strip()
        if "=" not in assign:
            out("export: mock expects NAME=value\n", done=True, exit_code=1)
        else:
            name, _, val = assign.partition("=")
            name = name.strip()
            val = val.strip().strip("'\"")
            st_x = _session_state(sk)
            env = st_x.setdefault("env", {})
            if not isinstance(env, dict):
                env = {}
                st_x["env"] = env
            env[name] = val
            out("", done=True, exit_code=0)


    elif lower.startswith("base64 ") or lower in {"base64", "base64 --help"}:
        import base64 as _b64
        parts = data.strip().split(None, 1)
        args = parts[1] if len(parts) > 1 else ""
        decode = "-d" in lower or "--decode" in lower or "-D" in lower
        # strip flags
        tokens = args.split()
        path = None
        raw_bits = []
        for t in tokens:
            if t.startswith("-"):
                continue
            if path is None:
                path = t
            else:
                raw_bits.append(t)
        if path is None and not raw_bits:
            out("base64: missing input (mock: path or literal)\n", done=True, exit_code=1)
        else:
            content = None
            if path:
                st_b = _session_state(sk)
                wd = st_b.get("workdir") or "/workspace"
                if path.startswith("/"):
                    rel = path.replace("/workspace", "").lstrip("/")
                else:
                    base = wd.replace("/workspace", "").lstrip("/")
                    rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
                node, _ = _ws_resolve(rel)
                if node and node.get("type") == "file":
                    content = node.get("content") or ""
                elif raw_bits:
                    content = " ".join([path] + raw_bits)
                else:
                    # treat path as literal string
                    content = path
            else:
                content = " ".join(raw_bits)
            try:
                if decode:
                    pad = (-len(content.strip())) % 4
                    raw = _b64.b64decode(content.strip() + ("=" * pad))
                    out(raw.decode("utf-8", errors="replace"), done=True, exit_code=0)
                else:
                    out(_b64.b64encode(content.encode("utf-8")).decode("ascii") + "\n", done=True, exit_code=0)
            except Exception as e:
                out(f"base64: {e}\n", done=True, exit_code=1)
    elif lower.startswith("file ") or lower == "file":
        arg = data.strip()[4:].strip() if lower.startswith("file") else ""
        if not arg:
            out("file: missing operand\n", done=True, exit_code=1)
        else:
            st_f = _session_state(sk)
            wd = st_f.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None:
                out(f"{arg}: cannot open (No such file or directory)\n", done=True, exit_code=1)
            elif node.get("type") == "dir":
                out(f"{cleaned or arg}: directory\n", done=True, exit_code=0)
            else:
                name = cleaned or arg
                content = node.get("content") or ""
                if name.endswith((".py",)):
                    kind = "Python script text"
                elif name.endswith((".md", ".markdown")):
                    kind = "Markdown text"
                elif name.endswith((".json",)):
                    kind = "JSON text"
                elif name.endswith((".sh", ".bash")):
                    kind = "Bourne-Again shell script text"
                else:
                    kind = "ASCII text" if content.isascii() else "UTF-8 text"
                out(f"{name}: {kind}\n", done=True, exit_code=0)
    elif lower.startswith("uniq") or lower == "uniq":
        args = data.strip().split(None, 1)
        payload = args[1] if len(args) > 1 else ""
        if not payload:
            out("uniq: (mock) pass tokens/lines to dedupe\n", done=True, exit_code=0)
        else:
            lines = payload.splitlines() if "\n" in payload else payload.split()
            out_lines = []
            prev = object()
            for ln in lines:
                if ln != prev:
                    out_lines.append(ln)
                    prev = ln
            out("\n".join(out_lines) + ("\n" if out_lines else ""), done=True, exit_code=0)
    elif lower.startswith("type ") or lower == "type":
        # bash type/command -v style
        name = data.strip()[4:].strip() if lower.startswith("type") else ""
        if not name:
            out("type: missing operand\n", done=True, exit_code=1)
        else:
            builtins = MOCK_TERM_BUILTINS
            if name.split()[0] in builtins:
                out(f"{name.split()[0]} is a shell builtin\n", done=True, exit_code=0)
            else:
                out(f"type: {name}: not found\n", done=True, exit_code=1)


    elif lower.startswith("md5sum") or lower.startswith("sha256sum") or lower.startswith("sha1sum"):
        import hashlib as _hl
        parts = data.strip().split()
        cmd = parts[0].lower() if parts else "md5sum"
        algo = "md5" if "md5" in cmd else ("sha1" if "sha1" in cmd else "sha256")
        targets = [p for p in parts[1:] if not p.startswith("-")]
        if not targets:
            out(f"{cmd}: missing file operand\n", done=True, exit_code=1)
        else:
            lines_out = []
            st_h = _session_state(sk)
            wd = st_h.get("workdir") or "/workspace"
            for path in targets:
                if path.startswith("/"):
                    rel = path.replace("/workspace", "").lstrip("/")
                else:
                    base = wd.replace("/workspace", "").lstrip("/")
                    rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
                node, cleaned = _ws_resolve(rel)
                if node is None or node.get("type") != "file":
                    lines_out.append(f"{cmd}: {path}: No such file or directory")
                    continue
                content = (node.get("content") or "").encode("utf-8")
                h = getattr(_hl, algo)(content).hexdigest()
                lines_out.append(f"{h}  {cleaned or path}")
            out("\n".join(lines_out) + "\n", done=True, exit_code=0)
    elif lower.startswith("nl ") or lower == "nl":
        arg = data.strip()[2:].strip() if lower.startswith("nl") else ""
        # strip -ba style flags
        while arg.startswith("-"):
            bits = arg.split(None, 1)
            arg = bits[1] if len(bits) > 1 else ""
        if not arg:
            out("nl: missing file operand\n", done=True, exit_code=1)
        else:
            st_n = _session_state(sk)
            wd = st_n.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"nl: {arg}: No such file or directory\n", done=True, exit_code=1)
            else:
                content = node.get("content") or ""
                numbered = []
                for i, line in enumerate(content.splitlines(), 1):
                    numbered.append(f"{i:6}\t{line}")
                out("\n".join(numbered) + ("\n" if numbered else ""), done=True, exit_code=0)
    elif lower.startswith("cut ") or lower == "cut":
        # cut -dSEP -fN  TEXT  or cut -cN- path
        parts = data.strip().split()
        delim = "\t"
        fields = None
        chars = None
        rest = []
        i = 1
        while i < len(parts):
            t = parts[i]
            if t == "-d" and i + 1 < len(parts):
                delim = parts[i + 1]
                i += 2
                continue
            if t.startswith("-d") and len(t) > 2:
                delim = t[2:]
                i += 1
                continue
            if t == "-f" and i + 1 < len(parts):
                fields = parts[i + 1]
                i += 2
                continue
            if t.startswith("-f") and len(t) > 2:
                fields = t[2:]
                i += 1
                continue
            if t == "-c" and i + 1 < len(parts):
                chars = parts[i + 1]
                i += 2
                continue
            if t.startswith("-c") and len(t) > 2:
                chars = t[2:]
                i += 1
                continue
            if t.startswith("-"):
                i += 1
                continue
            rest.append(t)
            i += 1
        payload = " ".join(rest)
        if not payload:
            out("cut: missing operand\n", done=True, exit_code=1)
        else:
            # try resolve as file else use as text
            st_c = _session_state(sk)
            wd = st_c.get("workdir") or "/workspace"
            path = payload
            if path.startswith("/"):
                rel = path.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
            node, _ = _ws_resolve(rel)
            text = (node.get("content") if node and node.get("type") == "file" else payload) or ""
            out_lines = []
            for line in text.splitlines() or [text]:
                if chars:
                    # simple N or N-M
                    try:
                        if "-" in chars:
                            a, b = chars.split("-", 1)
                            a_i = int(a) - 1 if a else 0
                            b_i = int(b) if b else len(line)
                            out_lines.append(line[max(0, a_i):b_i])
                        else:
                            ci = int(chars) - 1
                            out_lines.append(line[ci] if 0 <= ci < len(line) else "")
                    except Exception:
                        out_lines.append(line)
                elif fields:
                    cols = line.split(delim)
                    idxs = []
                    for part in fields.split(","):
                        part = part.strip()
                        if not part:
                            continue
                        try:
                            if "-" in part:
                                a, b = part.split("-", 1)
                                a_i = int(a) if a else 1
                                b_i = int(b) if b else len(cols)
                                idxs.extend(range(a_i, b_i + 1))
                            else:
                                idxs.append(int(part))
                        except Exception:
                            continue
                    picked = []
                    for ix in idxs:
                        if 1 <= ix <= len(cols):
                            picked.append(cols[ix - 1])
                    out_lines.append(delim.join(picked))
                else:
                    out_lines.append(line)
            out("\n".join(out_lines) + ("\n" if out_lines else ""), done=True, exit_code=0)


    elif lower.startswith("fold ") or lower == "fold":
        parts = data.strip().split()
        width = 80
        path = None
        i = 1
        while i < len(parts):
            t = parts[i]
            if t in {"-w", "--width"} and i + 1 < len(parts):
                try:
                    width = max(8, min(200, int(parts[i + 1])))
                except Exception:
                    pass
                i += 2
                continue
            if t.startswith("-w") and len(t) > 2 and t[2:].isdigit():
                width = max(8, min(200, int(t[2:])))
                i += 1
                continue
            if t.startswith("-"):
                i += 1
                continue
            path = t
            i += 1
        if not path:
            out("fold: missing file operand\n", done=True, exit_code=1)
        else:
            st_f = _session_state(sk)
            wd = st_f.get("workdir") or "/workspace"
            if path.startswith("/"):
                rel = path.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
            node, _ = _ws_resolve(rel)
            text = (node.get("content") if node and node.get("type") == "file" else path) or ""
            out_lines = []
            for line in text.splitlines() or [text]:
                if not line:
                    out_lines.append("")
                    continue
                for j in range(0, len(line), width):
                    out_lines.append(line[j : j + width])
            out("\n".join(out_lines) + ("\n" if out_lines else ""), done=True, exit_code=0)
    elif lower.startswith("hexdump") or lower.startswith("xxd ") or lower == "xxd" or lower == "hexdump":
        parts = data.strip().split()
        path = next((p for p in parts[1:] if not p.startswith("-")), None)
        if not path:
            out("hexdump: missing file operand\n", done=True, exit_code=1)
        else:
            st_x = _session_state(sk)
            wd = st_x.get("workdir") or "/workspace"
            if path.startswith("/"):
                rel = path.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"hexdump: {path}: No such file or directory\n", done=True, exit_code=1)
            else:
                raw = (node.get("content") or "").encode("utf-8")
                lines = []
                for off in range(0, min(len(raw), 256), 16):
                    chunk = raw[off : off + 16]
                    hexpart = " ".join(f"{b:02x}" for b in chunk)
                    asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
                    lines.append(f"{off:08x}  {hexpart:<48}  |{asc}|")
                if len(raw) > 256:
                    lines.append(f"... ({len(raw)} bytes total, showing first 256)")
                out("\n".join(lines) + "\n", done=True, exit_code=0)
    elif lower.startswith("jq ") or lower == "jq":
        # minimal: jq . path  or jq . <<< json
        parts = data.strip().split(None, 2)
        # jq . file
        expr = "."
        path = None
        tokens = data.strip().split()
        for t in tokens[1:]:
            if t.startswith("-"):
                continue
            if t.startswith(".") and path is None and expr == ".":
                expr = t
                continue
            if path is None and not t.startswith("."):
                path = t
        if path is None:
            out("jq: (mock) usage: jq . <file.json>\n", done=True, exit_code=1)
        else:
            st_j = _session_state(sk)
            wd = st_j.get("workdir") or "/workspace"
            if path.startswith("/"):
                rel = path.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
            node, _ = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"jq: {path}: No such file or directory\n", done=True, exit_code=1)
            else:
                content = node.get("content") or ""
                try:
                    import json as _json
                    obj = _json.loads(content)
                    if expr in {".", ""}:
                        out(_json.dumps(obj, indent=2, ensure_ascii=False) + "\n", done=True, exit_code=0)
                    elif expr.startswith(".") and len(expr) > 1:
                        key = expr[1:].split(".")[0].split("[")[0]
                        if isinstance(obj, dict) and key in obj:
                            out(_json.dumps(obj[key], indent=2, ensure_ascii=False) + "\n", done=True, exit_code=0)
                        else:
                            out("null\n", done=True, exit_code=0)
                    else:
                        out(_json.dumps(obj, indent=2, ensure_ascii=False) + "\n", done=True, exit_code=0)
                except Exception as e:
                    out(f"jq: parse error: {e}\n", done=True, exit_code=1)


    elif lower.startswith("tr ") or lower == "tr":
        parts = data.strip().split()
        delete = False
        args = []
        for t in parts[1:]:
            if t in {"-d", "--delete"}:
                delete = True
                continue
            if t.startswith("-"):
                continue
            args.append(t)
        if len(args) < 1:
            out("tr: missing operand\n", done=True, exit_code=1)
        else:
            if delete:
                s1 = args[0]
                text = " ".join(args[1:]) if len(args) > 1 else ""
                out("".join(ch for ch in text if ch not in s1) + "\n", done=True, exit_code=0)
            else:
                if len(args) < 2:
                    out("tr: missing operand\n", done=True, exit_code=1)
                else:
                    s1, s2 = args[0], args[1]
                    text = " ".join(args[2:]) if len(args) > 2 else ""
                    table = {}
                    for i, ch in enumerate(s1):
                        table[ch] = s2[i] if i < len(s2) else (s2[-1] if s2 else ch)
                    out("".join(table.get(ch, ch) for ch in text) + "\n", done=True, exit_code=0)
    elif lower.startswith("rev ") or lower == "rev":
        arg = data.strip()[3:].strip() if lower.startswith("rev") else ""
        while arg.startswith("-"):
            bits = arg.split(None, 1)
            arg = bits[1] if len(bits) > 1 else ""
        if not arg:
            out("rev: missing operand\n", done=True, exit_code=1)
        else:
            st_r = _session_state(sk)
            wd = st_r.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, _ = _ws_resolve(rel)
            text = (node.get("content") if node and node.get("type") == "file" else arg) or ""
            out("\n".join(line[::-1] for line in text.splitlines()) + ("\n" if text else ""), done=True, exit_code=0)
    elif lower.startswith("cmp ") or lower == "cmp":
        parts = [p for p in data.strip().split()[1:] if not p.startswith("-")]
        if len(parts) < 2:
            out("cmp: missing operand\n", done=True, exit_code=1)
        else:
            st_c = _session_state(sk)
            wd = st_c.get("workdir") or "/workspace"
            contents = []
            ok = True
            for path in parts[:2]:
                if path.startswith("/"):
                    rel = path.replace("/workspace", "").lstrip("/")
                else:
                    base = wd.replace("/workspace", "").lstrip("/")
                    rel = "/".join(p for p in (base + "/" + path).split("/") if p and p != ".")
                node, cleaned = _ws_resolve(rel)
                if node is None or node.get("type") != "file":
                    out(f"cmp: {path}: No such file or directory\n", done=True, exit_code=2)
                    ok = False
                    break
                contents.append((cleaned or path, node.get("content") or ""))
            if ok:
                (n1, c1), (n2, c2) = contents
                if c1 == c2:
                    out("", done=True, exit_code=0)
                else:
                    lim = min(len(c1), len(c2))
                    pos = lim
                    for i in range(lim):
                        if c1[i] != c2[i]:
                            pos = i
                            break
                    out(f"{n1} {n2} differ: byte {pos + 1}\n", done=True, exit_code=1)


    elif lower.startswith("yes ") or lower == "yes":
        # mock: print a few lines only (avoid infinite)
        arg = data.strip()[3:].strip() if lower.startswith("yes") else ""
        msg = arg if arg else "y"
        out(("\n".join([msg] * 5) + "\n"), done=True, exit_code=0)
    elif lower.startswith("tee ") or lower == "tee":
        # mock: echo stdin-like args to output; "write" note only
        parts = data.strip().split()
        paths = [p for p in parts[1:] if not p.startswith("-")]
        # remaining treated as content if no file resolve
        content = " ".join(paths) if paths else ""
        note = f"(mock tee wrote {len(content)} bytes"
        if paths:
            note += f" → {paths[0]}"
        note += ")\n"
        out((content + ("\n" if content and not content.endswith("\n") else "")) + note, done=True, exit_code=0)
    elif lower.startswith("xargs ") or lower == "xargs":
        # mock: xargs echo a b c  → echo a b c once
        parts = data.strip().split()
        # drop xargs flags
        i = 1
        cmd_parts = []
        while i < len(parts):
            t = parts[i]
            if t.startswith("-") and t not in {"-"}:
                if t in {"-n", "-I", "-i", "-d"} and i + 1 < len(parts):
                    i += 2
                    continue
                i += 1
                continue
            cmd_parts = parts[i:]
            break
        if not cmd_parts:
            out("xargs: (mock) missing command\n", done=True, exit_code=1)
        else:
            out(" ".join(cmd_parts) + "\n", done=True, exit_code=0)
    elif lower.startswith("od ") or lower == "od":
        # mock octal dump (first 64 bytes)
        parts = data.strip().split()
        targets = [p for p in parts[1:] if not p.startswith("-")]
        if not targets:
            out("od: missing file operand\n", done=True, exit_code=1)
        else:
            st_od = _session_state(sk)
            wd = (st_od.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
            path = targets[0]
            rel = path
            if not path.startswith("/"):
                rel = (wd + "/" + path).strip("/") if wd else path
            else:
                rel = path.replace("/workspace", "").lstrip("/")
            node, cleaned = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"od: {path}: No such file or directory\n", done=True, exit_code=1)
            else:
                raw = (node.get("content") or "")[:64].encode("utf-8", errors="replace")
                lines = []
                for off in range(0, len(raw), 8):
                    chunk = raw[off : off + 8]
                    octs = " ".join(f"{b:03o}" for b in chunk)
                    lines.append(f"{off:07o} {octs}")
                out(("\n".join(lines) + ("\n" if lines else "")), done=True, exit_code=0)
    elif lower.startswith("expr ") or lower == "expr":
        # mock: expr N + M / - / *  (integers only)
        parts = data.strip().split()
        if len(parts) < 4:
            out("expr: (mock) usage: expr N OP M\n", done=True, exit_code=1)
        else:
            try:
                a = int(parts[1])
                op = parts[2]
                b = int(parts[3])
                if op == "+":
                    r = a + b
                elif op == "-":
                    r = a - b
                elif op in {"*", "\\*", "x"}:
                    r = a * b
                elif op == "/":
                    if b == 0:
                        out("expr: division by zero\n", done=True, exit_code=2)
                        r = None
                    else:
                        r = a // b
                elif op == "%":
                    if b == 0:
                        out("expr: division by zero\n", done=True, exit_code=2)
                        r = None
                    else:
                        r = a % b
                else:
                    out(f"expr: (mock) unsupported op {op}\n", done=True, exit_code=1)
                    r = None
                if r is not None:
                    out(f"{r}\n", done=True, exit_code=0)
            except Exception:
                out("expr: non-integer argument\n", done=True, exit_code=1)
    elif lower.startswith("test ") or lower == "test" or lower.startswith("[ ") or lower == "[":
        # mock test/[ : -n/-z string, -eq/-ne/-lt/-gt numbers, -f/-d path
        raw = data.strip()
        if raw.startswith("["):
            raw = raw[1:].strip()
            if raw.endswith("]"):
                raw = raw[:-1].strip()
        elif raw.lower().startswith("test"):
            raw = raw[4:].strip()
        parts = raw.split()
        if not parts:
            out("", done=True, exit_code=1)
        else:
            ok = False
            try:
                if parts[0] == "-n" and len(parts) >= 2:
                    ok = len(parts[1]) > 0
                elif parts[0] == "-z" and len(parts) >= 2:
                    ok = len(parts[1]) == 0
                elif parts[0] in {"-f", "-d"} and len(parts) >= 2:
                    st_t = _session_state(sk)
                    wd = (st_t.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
                    path = parts[1]
                    rel = path
                    if not path.startswith("/"):
                        rel = (wd + "/" + path).strip("/") if wd else path
                    else:
                        rel = path.replace("/workspace", "").lstrip("/")
                    node, _ = _ws_resolve(rel)
                    if parts[0] == "-f":
                        ok = bool(node and node.get("type") == "file")
                    else:
                        ok = bool(node and node.get("type") == "dir") or (rel == "" or path in {"/workspace", "."})
                elif len(parts) >= 3 and parts[1] in {"-eq", "-ne", "-lt", "-gt", "-le", "-ge"}:
                    a = int(parts[0])
                    b = int(parts[2])
                    op = parts[1]
                    ok = {
                        "-eq": a == b,
                        "-ne": a != b,
                        "-lt": a < b,
                        "-gt": a > b,
                        "-le": a <= b,
                        "-ge": a >= b,
                    }[op]
                elif len(parts) >= 3 and parts[1] in {"=", "!="}:
                    ok = (parts[0] == parts[2]) if parts[1] == "=" else (parts[0] != parts[2])
                else:
                    ok = bool(parts[0])
            except Exception:
                ok = False
            out("", done=True, exit_code=0 if ok else 1)

    elif lower == "nproc" or lower == "nproc --all":
        # mock fixed CPU count (demo only — not real nproc)
        out("4\n", done=True, exit_code=0)
    elif lower.startswith("factor ") or lower == "factor":
        # mock factor: trial division; refuse |N| > 10**12
        parts = data.strip().split()
        if len(parts) < 2:
            out("factor: missing operand\nUsage: factor NUMBER\n", done=True, exit_code=1)
        else:
            raw_n = parts[1]
            try:
                n = int(raw_n)
            except ValueError:
                out(f"factor: '{raw_n}' is not a valid positive integer\n", done=True, exit_code=1)
            else:
                if abs(n) > 10**12:
                    out(f"factor: '{raw_n}' is too large (mock cap 10^12)\n", done=True, exit_code=1)
                elif n == 0:
                    out("0:\n", done=True, exit_code=0)
                else:
                    # factor positive magnitude; keep sign only for display of original
                    m = abs(n)
                    factors: List[int] = []
                    d = 2
                    while d * d <= m:
                        while m % d == 0:
                            factors.append(d)
                            m //= d
                        d += 1 if d == 2 else 2
                    if m > 1:
                        factors.append(m)
                    out(f"{n}: {' '.join(str(p) for p in factors)}\n", done=True, exit_code=0)
    elif lower.startswith("bc ") or lower == "bc" or lower.startswith("bc -e ") or lower.startswith("bc -e"):
        # simple mock calculator: integers + - * / % and parentheses via sanitized eval
        raw = data.strip()
        expr = ""
        # support: bc EXPR | bc -e EXPR | bc -e 'EXPR'
        if lower == "bc":
            expr = ""
        else:
            rest = raw[2:].strip()  # after "bc"
            if rest.lower().startswith("-e"):
                rest = rest[2:].strip()
            # strip one layer of matching quotes
            if (rest.startswith("'") and rest.endswith("'")) or (rest.startswith('"') and rest.endswith('"')):
                if len(rest) >= 2:
                    rest = rest[1:-1]
            expr = rest
        # join is already via rest; allow spaces in expression
        if not expr or not expr.strip():
            out("bc: (mock) empty expression\n", done=True, exit_code=1)
        else:
            sanitized = expr.strip()
            if not re.fullmatch(r"[0-9+\-*/%() \t]+", sanitized):
                out("bc: (mock) invalid characters (only digits and + - * / % ( ) allowed)\n", done=True, exit_code=1)
            else:
                try:
                    # integer-only arithmetic; use // for / via custom? keep Python / for floats then int if whole
                    # Prefer integer ops: replace bare / with // only between numbers is hard; eval then require int
                    val = eval(sanitized, {"__builtins__": {}}, {})  # noqa: S307 — sanitized digits/ops only
                    if isinstance(val, float):
                        if val != int(val):
                            # still report float as int truncation? reject non-int results for mock simplicity
                            out(f"{val}\n", done=True, exit_code=0)
                        else:
                            out(f"{int(val)}\n", done=True, exit_code=0)
                    else:
                        out(f"{int(val)}\n", done=True, exit_code=0)
                except ZeroDivisionError:
                    out("bc: division by zero\n", done=True, exit_code=1)
                except Exception:
                    out("bc: (mock) expression error\n", done=True, exit_code=1)

    elif lower == "arch":
        # mock fixed arch (demo only — not real arch)
        out("x86_64\n", done=True, exit_code=0)
    elif lower.startswith("getconf ") or lower == "getconf":
        # mock getconf: only a few keys (NPROCESSORS_ONLN / PAGE_SIZE family)
        parts = data.strip().split()
        if len(parts) < 2:
            out("getconf: missing operand\nUsage: getconf NAME\n", done=True, exit_code=1)
        else:
            key = parts[1]
            if key in {"NPROCESSORS_ONLN", "_NPROCESSORS_ONLN"}:
                out("4\n", done=True, exit_code=0)
            elif key in {"PAGE_SIZE", "PAGESIZE"}:
                out("4096\n", done=True, exit_code=0)
            else:
                out("getconf: (mock) unknown key\n", done=True, exit_code=1)
    elif lower.startswith("numfmt ") or lower == "numfmt":
        # mock numfmt: simple humanize --to=iec (1024) / --to=si (1000)
        parts = data.strip().split()
        to = "iec"
        n_raw = None
        if len(parts) == 1:
            out("numfmt: missing operand\n", done=True, exit_code=1)
        else:
            i = 1
            while i < len(parts):
                p = parts[i]
                if p.startswith("--to="):
                    to = p.split("=", 1)[1].lower()
                    i += 1
                elif p == "--to" and i + 1 < len(parts):
                    to = parts[i + 1].lower()
                    i += 2
                else:
                    n_raw = p
                    break
            if n_raw is None:
                out("numfmt: missing operand\n", done=True, exit_code=1)
            else:
                try:
                    n = int(n_raw)
                except ValueError:
                    out("numfmt: invalid number\n", done=True, exit_code=1)
                else:
                    if to not in {"iec", "si"}:
                        out("numfmt: (mock) unsupported --to\n", done=True, exit_code=1)
                    else:
                        base = 1024 if to == "iec" else 1000
                        units = ["", "K", "M", "G", "T", "P"]
                        v = float(abs(n))
                        u = 0
                        while v >= base and u < len(units) - 1:
                            v /= base
                            u += 1
                        sign = "-" if n < 0 else ""
                        if u == 0:
                            out(f"{sign}{int(v)}\n", done=True, exit_code=0)
                        else:
                            out(f"{sign}{v:.1f}{units[u]}\n", done=True, exit_code=0)

    elif lower == "logname":
        # mock fixed login name (demo only)
        out("huan\n", done=True, exit_code=0)
    elif lower == "groups":
        # mock fixed groups list (demo only)
        out("huan sudo docker\n", done=True, exit_code=0)
    elif lower.startswith("printenv ") or lower == "printenv":
        # mock printenv: fixed env dump, or single KEY lookup
        mock_env = {
            "PATH": "/usr/bin",
            "HOME": "/home/huan",
            "USER": "huan",
            "SHELL": "/bin/bash",
            "LANG": "en_US.UTF-8",
            "PWD": "/workspace",
        }
        if lower == "printenv":
            lines = [f"{k}={v}" for k, v in mock_env.items()]
            out("\n".join(lines) + "\n", done=True, exit_code=0)
        else:
            key = data.strip()[8:].strip().split()[0] if data.strip()[8:].strip() else ""
            if not key:
                out("", done=True, exit_code=1)
            elif key in mock_env:
                out(mock_env[key] + "\n", done=True, exit_code=0)
            else:
                out("", done=True, exit_code=1)

    elif lower == "users":
        # mock fixed logged-in users list (demo only)
        out("huan\n", done=True, exit_code=0)
    elif lower == "tty":
        # mock fixed tty path (demo only — not a real PTY)
        out("/dev/pts/0\n", done=True, exit_code=0)
    elif lower == "who" or lower == "who am i":
        # mock fixed who line (demo only)
        out("huan pts/0 2026-07-18 07:00 (mock)\n", done=True, exit_code=0)

    elif lower == "w":
        # mock w summary (demo only)
        out(
            " 07:00:00 up 1 day,  1 user,  load average: 0.00, 0.00, 0.00\n"
            "USER     TTY      FROM             LOGIN@   IDLE   JCPU   PCPU WHAT\n"
            "huan     pts/0    mock             07:00    0.00s  0.00s  0.00s mock-sh\n",
            done=True,
            exit_code=0,
        )
    elif lower == "last":
        out(
            "huan     pts/0        mock             Sat Jul 18 07:00   still logged in\n"
            "huan     pts/1        mock             Fri Jul 17 21:00 - 22:00  (01:00)\n"
            "\nwtmp begins Fri Jul 17 00:00:00 2026\n",
            done=True,
            exit_code=0,
        )
    elif lower == "cal" or lower.startswith("cal "):
        out(
            "     July 2026\n"
            "Su Mo Tu We Th Fr Sa\n"
            "          1  2  3  4\n"
            " 5  6  7  8  9 10 11\n"
            "12 13 14 15 16 17 18\n"
            "19 20 21 22 23 24 25\n"
            "26 27 28 29 30 31\n",
            done=True,
            exit_code=0,
        )

    elif lower == "lscpu" or lower.startswith("lscpu "):
        # mock fixed CPU summary (demo only)
        out(
            "Architecture:                    x86_64\n"
            "CPU(s):                          4\n"
            "Model name:                      Mock CPU\n",
            done=True,
            exit_code=0,
        )
    elif lower.startswith("fmt ") or lower == "fmt":
        # mock fmt: word-wrap text; optional -w N (default 80)
        parts = data.strip().split()
        if len(parts) < 2:
            out("fmt: missing operand\n", done=True, exit_code=1)
        else:
            width = 80
            text_parts = parts[1:]
            if text_parts and text_parts[0] == "-w":
                if len(text_parts) < 3:
                    out("fmt: option requires an argument -- 'w'\n", done=True, exit_code=1)
                    text_parts = None
                else:
                    try:
                        width = int(text_parts[1])
                        if width < 1:
                            raise ValueError("width")
                        text_parts = text_parts[2:]
                    except ValueError:
                        out("fmt: invalid width\n", done=True, exit_code=1)
                        text_parts = None
            if text_parts is not None:
                if not text_parts:
                    out("fmt: missing operand\n", done=True, exit_code=1)
                else:
                    words = " ".join(text_parts).split()
                    lines = []
                    cur = ""
                    for w in words:
                        if not cur:
                            cur = w
                        elif len(cur) + 1 + len(w) <= width:
                            cur = cur + " " + w
                        else:
                            lines.append(cur)
                            cur = w
                    if cur:
                        lines.append(cur)
                    out(("\n".join(lines) + ("\n" if lines else "")), done=True, exit_code=0)
    elif lower.startswith("shuf ") or lower == "shuf":
        # mock shuf: -e items; optional -n K; deterministic reverse+rotate (no random import)
        parts = data.strip().split()
        items = []
        n_limit = None
        i = 1
        ok = True
        while i < len(parts):
            p = parts[i]
            if p == "-n":
                if i + 1 >= len(parts):
                    out("shuf: option requires an argument -- 'n'\n", done=True, exit_code=1)
                    ok = False
                    break
                try:
                    n_limit = int(parts[i + 1])
                    if n_limit < 0:
                        raise ValueError("n")
                except ValueError:
                    out("shuf: invalid count\n", done=True, exit_code=1)
                    ok = False
                    break
                i += 2
            elif p == "-e":
                items.extend(parts[i + 1 :])
                break
            else:
                # treat bare args after flags as -e style list for demo
                items.extend(parts[i:])
                break
        if ok:
            if not items:
                out("shuf: no lines to shuffle\n", done=True, exit_code=1)
            else:
                # deterministic pseudo-shuffle: reverse then rotate by len//2
                items = list(reversed(items))
                rot = len(items) // 2
                items = items[rot:] + items[:rot]
                if n_limit is not None:
                    items = items[:n_limit]
                out(("\n".join(items) + ("\n" if items else "")), done=True, exit_code=0)


    elif lower.startswith("paste ") or lower == "paste":
        # mock paste: join args with TAB (demo; no file paste)
        parts = data.strip().split()
        if len(parts) < 2:
            out("paste: missing file operand\n", done=True, exit_code=1)
        else:
            out("\t".join(parts[1:]) + "\n", done=True, exit_code=0)
    elif lower.startswith("column ") or lower == "column":
        # mock column: join with two spaces; -t keeps space-separated columns on one line
        parts = data.strip().split()
        if len(parts) < 2:
            out("column: missing operand\n", done=True, exit_code=1)
        else:
            args = parts[1:]
            if args and args[0] == "-t":
                args = args[1:]
                if not args:
                    out("column: missing operand\n", done=True, exit_code=1)
                else:
                    out("  ".join(args) + "\n", done=True, exit_code=0)
            else:
                out("  ".join(args) + "\n", done=True, exit_code=0)
    elif lower.startswith("comm ") or lower == "comm":
        # mock comm: compare two tokens as single-line "files"
        parts = data.strip().split()
        if len(parts) != 3:
            out("comm: missing operand\n", done=True, exit_code=1)
        else:
            a, b = parts[1], parts[2]
            if a == b:
                out("\t\t" + a + "\n", done=True, exit_code=0)
            else:
                out(a + "\n\t" + b + "\n", done=True, exit_code=0)


    elif lower.startswith("join ") or lower == "join":
        # mock join: require two args; print A\tB (demo; no file join)
        parts = data.strip().split()
        if len(parts) != 3:
            out("join: usage: join A B\n", done=True, exit_code=1)
        else:
            a, b = parts[1], parts[2]
            if not a or not b:
                out("join: empty field\n", done=True, exit_code=1)
            else:
                out(a + "\t" + b + "\n", done=True, exit_code=0)
    elif lower.startswith("split ") or lower == "split":
        # mock split: split STR on space or -d X delimiter; one field per line
        parts = data.strip().split()
        if len(parts) < 2:
            out("split: usage: split [-d X] STR\n", done=True, exit_code=1)
        else:
            delim = " "
            args = parts[1:]
            if args and args[0] == "-d":
                if len(args) < 3:
                    out("split: usage: split [-d X] STR\n", done=True, exit_code=1)
                    args = None
                else:
                    delim = args[1]
                    args = args[2:]
            if args is not None:
                if not args:
                    out("split: usage: split [-d X] STR\n", done=True, exit_code=1)
                else:
                    text = " ".join(args)
                    if delim == "":
                        fields = list(text)
                    else:
                        fields = text.split(delim)
                    out(("\n".join(fields) + ("\n" if fields else "")), done=True, exit_code=0)
    elif lower.startswith("getent ") or lower == "getent":
        # mock getent: passwd/hosts/group demos only
        parts = data.strip().split()
        if len(parts) < 3:
            out("getent: missing operand\n", done=True, exit_code=1)
        else:
            db = parts[1].lower()
            key = parts[2]
            if db == "passwd" and key == "huan":
                out("huan:x:1000:1000:Huan:/home/huan:/bin/bash\n", done=True, exit_code=0)
            elif db == "hosts" and key == "localhost":
                out("127.0.0.1 localhost\n", done=True, exit_code=0)
            elif db == "group" and key == "huan":
                out("huan:x:1000:\n", done=True, exit_code=0)
            else:
                out(f"getent: {db} {key}: not found\n", done=True, exit_code=1)


    elif lower == "locale" or lower.startswith("locale "):
        # mock locale: fixed C.UTF-8 env dump / -a list (demo)
        parts = data.strip().split()
        if len(parts) == 1:
            out("LANG=C.UTF-8\nLC_ALL=C.UTF-8\n", done=True, exit_code=0)
        elif len(parts) == 2 and parts[1] == "-a":
            out("C\nC.UTF-8\nen_US.UTF-8\n", done=True, exit_code=0)
        else:
            out("locale: usage: locale [-a]\n", done=True, exit_code=1)
    elif lower == "umask" or lower.startswith("umask "):
        # mock umask: report 0022; set is no-op for valid octal mode
        parts = data.strip().split()
        if len(parts) == 1:
            out("0022\n", done=True, exit_code=0)
        elif len(parts) == 2 and re.fullmatch(r"0?[0-7]{3}", parts[1]):
            out("", done=True, exit_code=0)
        else:
            out("umask: invalid mode\n", done=True, exit_code=1)
    elif lower.startswith("readlink ") or lower == "readlink":
        # mock readlink: echo path; -f -> /workspace-style absolute cleaned path
        parts = data.strip().split()
        if len(parts) < 2:
            out("readlink: missing operand\n", done=True, exit_code=1)
        else:
            flags = set()
            path_bits = []
            for p in parts[1:]:
                if p in ("-f", "-n", "--"):
                    if p != "--":
                        flags.add(p)
                    continue
                if p.startswith("-") and path_bits == []:
                    # ignore other short flags in mock
                    continue
                path_bits.append(p)
            if not path_bits:
                out("readlink: missing operand\n", done=True, exit_code=1)
            else:
                target = path_bits[0]
                if "-f" in flags:
                    # cleaned absolute under /workspace style
                    if target.startswith("/"):
                        cleaned = "/" + "/".join(x for x in target.split("/") if x and x != ".")
                    else:
                        cleaned = "/workspace/" + "/".join(x for x in target.split("/") if x and x != ".")
                    # collapse .. simply by skipping (mock)
                    segs = []
                    for seg in cleaned.split("/"):
                        if seg == "" or seg == ".":
                            continue
                        if seg == "..":
                            if segs:
                                segs.pop()
                            continue
                        segs.append(seg)
                    cleaned = "/" + "/".join(segs) if segs else "/"
                    out(cleaned + "\n", done=True, exit_code=0)
                else:
                    out(target + "\n", done=True, exit_code=0)

    elif lower.startswith("cksum ") or lower == "cksum":
        # mock cksum: CRC (sum ord % 65535), byte length, name token(s)
        parts = data.strip().split()
        if len(parts) < 2:
            out("cksum: usage: cksum TEXT\n", done=True, exit_code=1)
        else:
            text = " ".join(parts[1:])
            crc = sum(ord(c) for c in text) % 65535
            out(f"{crc} {len(text)} {text}\n", done=True, exit_code=0)
    elif lower.startswith("sum ") or lower == "sum":
        # mock sum: fixed demo checksum line
        parts = data.strip().split()
        if len(parts) < 2:
            out("sum: usage: sum TEXT\n", done=True, exit_code=1)
        else:
            out("0042 1\n", done=True, exit_code=0)
    elif lower.startswith("expand ") or lower == "expand":
        # mock expand: tabs -> spaces (tabstop 8); preserve tabs via maxsplit=1
        parts = data.strip().split(maxsplit=1)
        if len(parts) < 2:
            out("expand: missing operand\n", done=True, exit_code=1)
        else:
            text = parts[1]
            out_chars = []
            col = 0
            for ch in text:
                if ch == "\t":
                    spaces = 8 - (col % 8)
                    out_chars.append(" " * spaces)
                    col += spaces
                else:
                    out_chars.append(ch)
                    if ch == "\n":
                        col = 0
                    else:
                        col += 1
            out("".join(out_chars) + "\n", done=True, exit_code=0)

    elif lower.startswith("unexpand ") or lower == "unexpand":
        # mock unexpand: runs of 8 spaces -> tab (tabstop 8 simple)
        # split on first space only so operand spaces are preserved (not collapsed)
        parts = data.strip().split(" ", 1)
        if len(parts) < 2 or parts[1] == "":
            out("unexpand: missing operand\n", done=True, exit_code=1)
        else:
            text = parts[1]
            out(text.replace("        ", "\t") + "\n", done=True, exit_code=0)
    elif lower.startswith("tac ") or lower == "tac":
        # mock tac: print args reversed one per line
        parts = data.strip().split()
        if len(parts) < 2:
            out("tac: missing operand\n", done=True, exit_code=1)
        else:
            out("\n".join(reversed(parts[1:])) + "\n", done=True, exit_code=0)
    elif lower.startswith("namei ") or lower == "namei":
        # mock namei: path component listing (demo only)
        parts = data.strip().split(maxsplit=1)
        if len(parts) < 2 or not parts[1].strip():
            out("namei: missing operand\n", done=True, exit_code=1)
        else:
            path_arg = parts[1].strip()
            lines = [f"f: {path_arg}"]
            # normalize leading /
            rest = path_arg
            if rest.startswith("/"):
                lines.append(" d /")
                rest = rest.lstrip("/")
            segs = [s for s in rest.split("/") if s]
            for i, seg in enumerate(segs):
                kind = "f" if i == len(segs) - 1 else "d"
                lines.append(f" {kind} {seg}")
            out("\n".join(lines) + "\n", done=True, exit_code=0)

    elif lower in {"dir", "dir -a"} or lower.startswith("dir "):
        # mock dir: alias of ls — list mock workspace entries
        st_dir = _session_state(sk)
        rel = (st_dir.get("workdir") or "/workspace").replace("/workspace", "").lstrip("/")
        node, _ = _ws_resolve(rel)
        if node is None or node.get("type") == "file":
            # fixed demo listing fallback
            out("AGENTS.md\nCHANGELOG.md\napps/\ndocs/\nserver/\n", done=True, exit_code=0)
        else:
            kids = node.get("children") or {}
            names = []
            for name, child in sorted(kids.items(), key=lambda x: (x[1].get("type") != "dir", x[0])):
                names.append(name + ("/" if child.get("type") == "dir" else ""))
            if names:
                out(("\n".join(names) + "\n"), done=True, exit_code=0)
            else:
                out("AGENTS.md\nCHANGELOG.md\napps/\ndocs/\nserver/\n", done=True, exit_code=0)
    elif lower.startswith("vdir ") or lower == "vdir":
        # mock vdir: long listing demo (fixed)
        out(
            "drwxr-xr-x 2 mock mock 4096 Jul 18 12:00 apps\n"
            "drwxr-xr-x 2 mock mock 4096 Jul 18 12:00 docs\n"
            "drwxr-xr-x 2 mock mock 4096 Jul 18 12:00 server\n"
            "-rw-r--r-- 1 mock mock  128 Jul 18 12:00 AGENTS.md\n"
            "-rw-r--r-- 1 mock mock  256 Jul 18 12:00 CHANGELOG.md\n",
            done=True,
            exit_code=0,
        )
    elif lower.startswith("tsort ") or lower == "tsort":
        # mock tsort: print unique tokens preserving first-occurrence order
        parts = data.strip().split()
        if len(parts) < 2:
            out("tsort: missing operand\n", done=True, exit_code=1)
        else:
            seen = []
            for tok in parts[1:]:
                if tok not in seen:
                    seen.append(tok)
            out("\n".join(seen) + "\n", done=True, exit_code=0)


    elif lower.startswith("pathchk ") or lower == "pathchk":
        # mock pathchk: silent success if path present and len<=4096; else exit 1
        parts = data.strip().split(maxsplit=1)
        if len(parts) < 2 or parts[1] == "":
            out("pathchk: missing operand\n", done=True, exit_code=1)
        else:
            p = parts[1]
            if len(p) > 4096:
                out("pathchk: path too long\n", done=True, exit_code=1)
            else:
                out("", done=True, exit_code=0)
    elif lower.startswith("mktemp ") or lower == "mktemp":
        # mock mktemp: fixed /tmp path; optional -t PREFIX
        parts = data.strip().split()
        if len(parts) >= 2 and parts[1] == "-t":
            if len(parts) < 3 or parts[2] == "":
                out("mktemp: option requires an argument -- t\n", done=True, exit_code=1)
            else:
                out(f"/tmp/{parts[2]}.ABCDEF\n", done=True, exit_code=0)
        else:
            out("/tmp/tmp.ABCDEF\n", done=True, exit_code=0)
    elif lower == "sync" or lower.startswith("sync "):
        # mock sync: flush no-op
        out("", done=True, exit_code=0)
    elif lower.startswith("link ") or lower == "link":
        # mock link: hardlink create TARGET LINK_NAME; silent success (no real FS)
        parts = data.strip().split()
        if len(parts) < 3:
            out("link: usage: link TARGET LINK_NAME\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("ln ") or lower == "ln":
        # mock ln: ln [-s] [-f] TARGET LINK; strip -s/-f; need 2 path args
        parts = data.strip().split()
        paths = []
        for p in parts[1:]:
            if p in ("-s", "-f"):
                continue
            if p.startswith("-") and len(p) > 1 and all(c in "sf" for c in p[1:]):
                continue
            paths.append(p)
        if len(paths) < 2:
            out("ln: missing file operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("truncate ") or lower == "truncate":
        # mock truncate: no-op success; -s SIZE optional; FILE required
        parts = data.strip().split()
        file_arg = None
        i = 1
        while i < len(parts):
            p = parts[i]
            if p == "-s":
                i += 2  # skip SIZE
                continue
            if p.startswith("-s") and len(p) > 2:
                i += 1  # -sSIZE
                continue
            if p.startswith("-") and p not in ("-s",):
                i += 1
                continue
            file_arg = p
            break
        if not file_arg:
            out("truncate: missing file operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)


    elif lower.startswith("install ") or lower == "install":
        # mock install: install [-m MODE] [-D] SRC DST; strip -m/-D; need 2 path args
        parts = data.strip().split()
        paths = []
        i = 1
        while i < len(parts):
            p = parts[i]
            if p == "-m":
                i += 2  # skip MODE
                continue
            if p.startswith("-m") and len(p) > 2:
                i += 1  # -mMODE
                continue
            if p == "-D":
                i += 1
                continue
            if p.startswith("-") and p not in ("-D", "-m"):
                i += 1
                continue
            paths.append(p)
            i += 1
        if len(paths) < 2:
            out("install: usage: install SRC DST\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("shred ") or lower == "shred":
        # mock shred: wipe FILE (optional -u); missing file exit 1; silent success
        parts = data.strip().split()
        paths = []
        for p in parts[1:]:
            if p == "-u":
                continue
            if p.startswith("-") and len(p) > 1 and all(c in "u" for c in p[1:]):
                continue
            paths.append(p)
        if not paths:
            out("shred: missing file operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("timeout ") or lower == "timeout":
        # mock timeout: timeout SECS CMD...; no real wait/sleep; silent success
        parts = data.strip().split()
        if len(parts) < 3:
            out("timeout: usage: timeout SECS CMD...\n", done=True, exit_code=1)
        else:
            secs = parts[1]
            if not re.fullmatch(r"[0-9]+", secs):
                out("timeout: invalid time interval\n", done=True, exit_code=1)
            else:
                out("", done=True, exit_code=0)

    elif lower.startswith("nice ") or lower == "nice":
        # mock nice: nice [-n N] CMD...; strip optional -n N; need CMD else usage 1; silent 0
        parts = data.strip().split()
        i = 1
        if i < len(parts) and parts[i] == "-n":
            i += 2  # skip N
        elif i < len(parts) and parts[i].startswith("-n") and len(parts[i]) > 2:
            i += 1  # -nN
        cmd_parts = parts[i:]
        if not cmd_parts:
            out("nice: usage: nice [-n N] CMD...\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("nohup ") or lower == "nohup":
        # mock nohup: nohup CMD...; need CMD else exit 1; print ignore msg; do not run CMD
        parts = data.strip().split()
        if len(parts) < 2:
            out("nohup: missing operand\n", done=True, exit_code=1)
        else:
            out("nohup: ignoring input and appending output to 'nohup.out'\n", done=True, exit_code=0)
    elif lower.startswith("watch ") or lower == "watch":
        # mock watch: watch [-n N] CMD; one snapshot line; NEVER loop/sleep
        parts = data.strip().split()
        i = 1
        interval = "2"
        if i < len(parts) and parts[i] == "-n":
            if i + 1 < len(parts):
                interval = parts[i + 1]
            i += 2
        elif i < len(parts) and parts[i].startswith("-n") and len(parts[i]) > 2:
            interval = parts[i][2:]
            i += 1
        cmd_parts = parts[i:]
        if not cmd_parts:
            out("watch: missing command\n", done=True, exit_code=1)
        else:
            cmd_str = " ".join(cmd_parts)
            out(f"Every {interval}s: {cmd_str}\nmock: ran once\n", done=True, exit_code=0)

    elif lower.startswith("stdbuf ") or lower == "stdbuf":
        # mock stdbuf: stdbuf [-oL|-eL|-i0 ...] CMD...; strip short flags; need CMD else 1; silent 0
        parts = data.strip().split()
        i = 1
        while i < len(parts) and parts[i].startswith("-") and parts[i] != "-":
            i += 1
        cmd_parts = parts[i:]
        if not cmd_parts:
            out("stdbuf: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("flock ") or lower == "flock":
        # mock flock: flock [-n|-x|-s] FILE [CMD...]; strip flags; need FILE; never block
        parts = data.strip().split()
        i = 1
        while i < len(parts) and parts[i] in {"-n", "-x", "-s"}:
            i += 1
        rest = parts[i:]
        if not rest:
            out("flock: missing file operand\n", done=True, exit_code=1)
        else:
            # FILE only or FILE + CMD — mock never blocks; silent success
            out("", done=True, exit_code=0)
    elif lower.startswith("ionice ") or lower == "ionice":
        # mock ionice: ionice [-c N] [-n N] CMD...; strip optional -c/-n; need CMD else 1; silent 0
        parts = data.strip().split()
        i = 1
        while i < len(parts):
            tok = parts[i]
            if tok in {"-c", "-n"}:
                i += 2  # skip value if present (may overshoot → empty CMD → usage)
                continue
            if (tok.startswith("-c") or tok.startswith("-n")) and len(tok) > 2 and tok[2:].isdigit():
                i += 1
                continue
            break
        cmd_parts = parts[i:]
        if not cmd_parts:
            out("ionice: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)

    elif lower.startswith("taskset ") or lower == "taskset":
        # mock taskset: taskset -c LIST CMD... or taskset MASK CMD; need CMD else 1; silent 0
        parts = data.strip().split()
        i = 1
        used_c = False
        if i < len(parts) and parts[i] == "-c":
            used_c = True
            i += 2  # skip -c and LIST (LIST may be missing → fail below)
        rest = parts[i:]
        if used_c:
            if not rest:
                out("taskset: missing operand\n", done=True, exit_code=1)
            else:
                out("", done=True, exit_code=0)
        else:
            # MASK CMD... form
            if len(rest) < 2:
                out("taskset: missing operand\n", done=True, exit_code=1)
            else:
                out("", done=True, exit_code=0)
    elif lower.startswith("prlimit ") or lower == "prlimit":
        # mock prlimit: bare or --pid N → fixed limits; CMD → silent 0; invalid --pid → 1
        parts = data.strip().split()
        limits = (
            "RESOURCE SOFT HARD\n"
            "NOFILE 1024 1048576\n"
            "NPROC  4096 unlimited\n"
            "AS     unlimited unlimited\n"
        )
        if len(parts) == 1:
            out(limits, done=True, exit_code=0)
        elif parts[1] == "--pid":
            if len(parts) < 3 or not re.fullmatch(r"[0-9]+", parts[2]):
                out("prlimit: invalid --pid\n", done=True, exit_code=1)
            elif len(parts) == 3:
                out(limits, done=True, exit_code=0)
            else:
                # --pid N CMD... silent success
                out("", done=True, exit_code=0)
        else:
            # prlimit CMD... silent success
            out("", done=True, exit_code=0)
    elif lower.startswith("chroot ") or lower == "chroot":
        # mock chroot: chroot NEWROOT [CMD...]; need NEWROOT else 1; silent 0
        parts = data.strip().split()
        if len(parts) < 2:
            out("chroot: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("unshare ") or lower == "unshare":
        # mock unshare: unshare CMD... or unshare -m CMD; strip short -m/-n/-p/-u/-i; need CMD else 1; silent 0
        parts = data.strip().split()
        i = 1
        while i < len(parts):
            tok = parts[i]
            if tok in {"-m", "-n", "-p", "-u", "-i"} or (
                tok.startswith("-") and tok != "-" and all(c in "mnpui" for c in tok[1:])
            ):
                i += 1
                continue
            break
        cmd_parts = parts[i:]
        if not cmd_parts:
            out("unshare: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("nsenter ") or lower == "nsenter":
        # mock nsenter: nsenter -t PID CMD... or nsenter CMD; strip optional -t PID and short flags; need CMD else 1; silent 0
        parts = data.strip().split()
        i = 1
        while i < len(parts):
            tok = parts[i]
            if tok == "-t":
                i += 2  # skip -t and PID (may overshoot → empty CMD → usage)
                continue
            if tok.startswith("-t") and len(tok) > 2 and tok[2:].isdigit():
                i += 1
                continue
            if tok.startswith("-") and tok != "-":
                i += 1
                continue
            break
        cmd_parts = parts[i:]
        if not cmd_parts:
            out("nsenter: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("setpriv ") or lower == "setpriv":
        # mock setpriv: setpriv CMD... or setpriv --reuid N CMD; strip tokens starting with -; need CMD else 1; silent 0
        parts = data.strip().split()
        i = 1
        while i < len(parts) and parts[i].startswith("-") and parts[i] != "-":
            i += 1
        cmd_parts = parts[i:]
        if not cmd_parts:
            out("setpriv: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)


    elif lower.startswith("capsh ") or lower == "capsh":
        # mock capsh: capsh --print or capsh -- CMD; --print/bare → fixed caps; flags stripped, need CMD else 1
        parts = data.strip().split()
        tokens = parts[1:]
        if not parts:
            out("capsh: missing operand\n", done=True, exit_code=1)
        elif any(t == "--print" for t in tokens) or not tokens:
            out("Current: =ep\nBounding set: =ep\n", done=True, exit_code=0)
        else:
            # strip flags starting with -; if CMD left silent 0 else exit 1
            i = 0
            while i < len(tokens):
                t = tokens[i]
                if t == "--":
                    i += 1
                    break
                if t.startswith("-") and t != "-":
                    i += 1
                    continue
                break
            cmd_parts = tokens[i:]
            if not cmd_parts:
                out("capsh: missing operand\n", done=True, exit_code=1)
            else:
                out("", done=True, exit_code=0)
    elif lower.startswith("runcon ") or lower == "runcon":
        # mock runcon: runcon CONTEXT CMD... or runcon CMD; need ≥1 arg else 1; silent 0 (no SELinux)
        parts = data.strip().split()
        if len(parts) < 2:
            out("runcon: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("ldd ") or lower == "ldd":
        # mock ldd: ldd FILE; need FILE else 1; fixed mock deps
        parts = data.strip().split()
        if len(parts) < 2:
            out("ldd: missing file arguments\n", done=True, exit_code=1)
        else:
            out(
                "linux-vdso.so.1 (0x0000)\tlibc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x0000)\n",
                done=True,
                exit_code=0,
            )

    elif lower.startswith("ldconfig ") or lower == "ldconfig":
        # mock ldconfig: bare or -p → fixed cache lines; other flags silent 0
        parts = data.strip().split()
        tokens = parts[1:]
        if not tokens or tokens == ["-p"] or (len(tokens) == 1 and tokens[0] == "-p"):
            out(
                "\tlibc.so.6 (libc6,x86-64) => /lib/x86_64-linux-gnu/libc.so.6\n",
                done=True,
                exit_code=0,
            )
        else:
            # strip unknown flags; always exit 0
            out("", done=True, exit_code=0)
    elif lower.startswith("uuidgen ") or lower == "uuidgen":
        # mock uuidgen: fixed UUID (no randomness); -r accepted
        out("00000000-0000-4000-8000-000000000001\n", done=True, exit_code=0)

    elif lower.startswith("rmdir ") or lower == "rmdir":
        # mock rmdir: rmdir DIR...; need ≥1 DIR else 1; silent 0 (no real delete / no tree mutate)
        parts = data.strip().split()
        if len(parts) < 2:
            out("rmdir: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("mkfifo ") or lower == "mkfifo":
        # mock mkfifo: mkfifo NAME...; need ≥1 NAME else 1; silent 0 (no real fifo / no tree mutate)
        parts = data.strip().split()
        if len(parts) < 2:
            out("mkfifo: missing operand\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)

    elif lower.startswith("getopt ") or lower == "getopt":
        # mock getopt: getopt OPTSTRING [ARGS...] or getopt -o OPTSTRING -- ARGS
        # need OPTSTRING else 1; no args → "--\n"; else " -- " + remaining + "\n"
        parts = data.strip().split()
        if len(parts) < 2:
            out("getopt: missing operand\n", done=True, exit_code=1)
        else:
            args = parts[1:]
            if args[0] in {"-o", "--options"}:
                if len(args) < 2:
                    out("getopt: missing operand\n", done=True, exit_code=1)
                else:
                    rest = args[2:]  # skip -o OPTSTRING
                    if rest and rest[0] == "--":
                        rest = rest[1:]
                    if not rest:
                        out("--\n", done=True, exit_code=0)
                    else:
                        out(" -- " + " ".join(rest) + "\n", done=True, exit_code=0)
            else:
                # OPTSTRING is args[0]
                rest = args[1:]
                if not rest:
                    out("--\n", done=True, exit_code=0)
                else:
                    out(" -- " + " ".join(rest) + "\n", done=True, exit_code=0)
    elif lower.startswith("strings ") or lower == "strings":
        # mock strings: strings FILE; need FILE else 1; fixed printable lines
        parts = data.strip().split()
        if len(parts) < 2:
            out("strings: missing operand\n", done=True, exit_code=1)
        else:
            out("hello\nworld\n", done=True, exit_code=0)
    elif lower.startswith("csplit ") or lower == "csplit":
        # mock csplit: csplit FILE [PATTERN]; need FILE else 1; fixed mock byte count; no tree mutate
        parts = data.strip().split()
        if len(parts) < 2:
            out("csplit: missing operand\n", done=True, exit_code=1)
        else:
            out("0\n", done=True, exit_code=0)

    elif lower.startswith("diff ") or lower == "diff":
        # mock diff: diff A B — need 2 files else exit 1; fixed unified-ish hunk, exit 1 (differences)
        parts = data.strip().split()
        if len(parts) < 3:
            out("diff: missing operand\n", done=True, exit_code=1)
        else:
            out("--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n", done=True, exit_code=1)
    elif lower.startswith("patch ") or lower == "patch":
        # mock patch: patch FILE [patchfile] — need ≥1 arg; print applied note; do NOT mutate WORKSPACE_TREE
        parts = data.strip().split()
        if len(parts) < 2:
            out("patch: missing operand\n", done=True, exit_code=1)
        else:
            out("[mock-patch] applied (demo)\n", done=True, exit_code=0)
    elif lower.startswith("sdiff ") or lower == "sdiff":
        # mock sdiff: sdiff A B — need 2 files else exit 1; fixed side-by-side demo lines, exit 1
        parts = data.strip().split()
        if len(parts) < 3:
            out("sdiff: missing operand\n", done=True, exit_code=1)
        else:
            out("old\t\t\t\tnew\n", done=True, exit_code=1)
    elif lower.startswith("diff3 ") or lower == "diff3":
        # mock diff3: diff3 A B C — need 3 files else exit 1; fixed 3-way conflict demo, exit 1
        parts = data.strip().split()
        if len(parts) < 4:
            out("diff3: missing operand\n", done=True, exit_code=1)
        else:
            out("====\n1:1c\n  a\n2:1c\n  b\n3:1c\n  c\n", done=True, exit_code=1)
    elif lower.startswith("pr ") or lower == "pr":
        # mock pr: pr FILE or bare — fixed page header demo; exit 0
        parts = data.strip().split()
        if len(parts) >= 2:
            fname = parts[1]
            out(f"\n\n2026-07-18 00:00\t\t{fname}\t\tPage 1\n\nline\n", done=True, exit_code=0)
        else:
            out("\n\n", done=True, exit_code=0)
    elif lower.startswith("sha512sum ") or lower == "sha512sum":
        # mock sha512sum: FILE or bare — fixed 128-hex digest + path (or -); exit 0
        parts = data.strip().split()
        digest = "0" * 128
        if len(parts) >= 2:
            out(f"{digest}  {parts[1]}\n", done=True, exit_code=0)
        else:
            out(f"{digest}  -\n", done=True, exit_code=0)
    elif lower.startswith("base32 ") or lower == "base32":
        # mock base32: base32 FILE | base32 | base32 -d — fixed encode/decode demo; exit 0
        parts = data.strip().split()
        if any(p == "-d" or p.startswith("-d") for p in parts[1:]):
            out("hello\n", done=True, exit_code=0)
        else:
            out("JBSWY3DPEBLW64TMMQ======\n", done=True, exit_code=0)
    elif lower.startswith("sha224sum ") or lower == "sha224sum":
        # mock sha224sum: FILE or bare — fixed 56-hex digest + path (or -); exit 0
        parts = data.strip().split()
        digest = "0" * 56
        if len(parts) >= 2:
            out(f"{digest}  {parts[1]}\n", done=True, exit_code=0)
        else:
            out(f"{digest}  -\n", done=True, exit_code=0)
    elif lower.startswith("sha384sum ") or lower == "sha384sum":
        # mock sha384sum: FILE or bare — fixed 96-hex digest + path (or -); exit 0
        parts = data.strip().split()
        digest = "0" * 96
        if len(parts) >= 2:
            out(f"{digest}  {parts[1]}\n", done=True, exit_code=0)
        else:
            out(f"{digest}  -\n", done=True, exit_code=0)
    elif lower.startswith("dircolors ") or lower == "dircolors":
        # mock dircolors: bare or with args — fixed LS_COLORS demo; exit 0
        parts = data.strip().split()
        if any(p in ("-b", "--sh", "--bourne-shell") for p in parts[1:]):
            out("export LS_COLORS='*.py=01;32:'\n", done=True, exit_code=0)
        else:
            out("LS_COLORS='*.py=01;32:'\n", done=True, exit_code=0)
    elif lower.startswith("tput ") or lower == "tput":
        # mock tput: cols→80, lines→24, clear→newline; bare/other→demo exit 0
        parts = data.strip().split()
        if len(parts) >= 2 and parts[1] == "cols":
            out("80\n", done=True, exit_code=0)
        elif len(parts) >= 2 and parts[1] == "lines":
            out("24\n", done=True, exit_code=0)
        elif len(parts) >= 2 and parts[1] == "clear":
            out("\n", done=True, exit_code=0)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("tset ") or lower == "tset":
        # mock tset: fixed terminal type demo; exit 0
        out("Terminal type is xterm-256color\n", done=True, exit_code=0)
    elif lower.startswith("tabs ") or lower == "tabs":
        # mock tabs: set to default demo; exit 0
        out("tabs: set to default\n", done=True, exit_code=0)
    elif lower.startswith("script ") or lower == "script":
        # mock script: bare or FILE — fixed start line; no real file / no WORKSPACE_TREE mutate
        out("Script started, file is typescript\n", done=True, exit_code=0)
    elif lower.startswith("scriptreplay ") or lower == "scriptreplay":
        # mock scriptreplay: bare or with args — fixed done line; exit 0
        out("scriptreplay: (mock) done\n", done=True, exit_code=0)
    elif lower.startswith("infocmp ") or lower == "infocmp":
        # mock infocmp: bare or TERM — short terminfo-ish dump; exit 0
        out("#\tReconstructed via mock\nxterm-256color|xterm with 256 colors,\n", done=True, exit_code=0)
    elif lower.startswith("toe ") or lower == "toe":
        # mock toe: list terminfo names demo; exit 0
        out("xterm-256color\nvt100\nansi\n", done=True, exit_code=0)
    elif lower.startswith("reset ") or lower == "reset":
        # mock reset: demo terminal reset (not real PTY); exit 0
        out("\n", done=True, exit_code=0)
    elif lower.startswith("resize ") or lower == "resize":
        # mock resize: fixed COLUMNS/LINES shell exports; exit 0
        out("COLUMNS=80;\nLINES=24;\nexport COLUMNS LINES;\n", done=True, exit_code=0)

    elif lower.startswith("login ") or lower == "login":
        # mock login: demo only — never real auth
        out("login: (mock) not a real login\n", done=True, exit_code=1)
    elif lower.startswith("mesg ") or lower == "mesg":
        # mock mesg: bare → is y; y/n/yes/no → empty exit 0
        parts = data.strip().split()
        if len(parts) == 1:
            out("is y\n", done=True, exit_code=0)
        else:
            arg = parts[1].lower()
            if arg in {"y", "n", "yes", "no"}:
                out("", done=True, exit_code=0)
            else:
                out("", done=True, exit_code=0)
    elif lower.startswith("write ") or lower == "write":
        # mock write: demo only — never real messaging
        out("write: (mock) user not logged in\n", done=True, exit_code=1)
    elif lower.startswith("wall ") or lower == "wall":
        # mock wall: fixed broadcast demo; exit 0
        out("Broadcast message from mock@mock-host (pts/0):\n\n(mock wall)\n", done=True, exit_code=0)
    elif lower.startswith("newgrp ") or lower == "newgrp":
        # mock newgrp: demo only — no real group change; empty exit 0
        out("", done=True, exit_code=0)
    elif lower.startswith("su ") or lower == "su":
        # mock su: demo only — never real auth
        out("su: (mock) Authentication failure\n", done=True, exit_code=1)
    elif lower.startswith("sudo ") or lower == "sudo":
        # mock sudo: demo only — never real privilege
        out("sudo: (mock) a password is required\n", done=True, exit_code=1)
    elif lower.startswith("chfn ") or lower == "chfn":
        # mock chfn: demo only — never real account change
        out("chfn: (mock) not permitted\n", done=True, exit_code=1)
    elif lower.startswith("chsh ") or lower == "chsh":
        # mock chsh: demo only — never real shell change
        out("chsh: (mock) not permitted\n", done=True, exit_code=1)
    elif lower.startswith("passwd ") or lower == "passwd":
        # mock passwd: demo only — never real auth
        out("passwd: (mock) Authentication token manipulation error\n", done=True, exit_code=1)
    elif lower.startswith("lastlog"):
        # mock lastlog: demo only — fixed output
        out("Username         Port     From             Latest\nmock             pts/0    127.0.0.1        Fri Jul 18 00:00:00 +0000 2026\n", done=True, exit_code=0)
    elif lower == "lastb" or lower.startswith("lastb "):
        # mock lastb: demo only — fixed failed-login output
        out(
            "mock     pts/0                         Fri Jul 18 00:00 - 00:01  (00:01)\n"
            "\n"
            "btmp begins Fri Jul 18 00:00:00 2026\n",
            done=True,
            exit_code=0,
        )
    elif lower == "faillog" or lower.startswith("faillog "):
        # mock faillog: demo only — fixed failure log output
        out(
            "Login               Failures    Maximum    Latest\n"
            "mock                     0        0\n",
            done=True,
            exit_code=0,
        )
    elif lower.startswith("chage") or lower == "chage":
        # mock chage: demo only — permission denied
        out("chage: (mock) permission denied\n", done=True, exit_code=1)
    elif lower.startswith("alias ") or lower == "alias":
        # mock alias: bare prints fixed aliases; with args — empty exit 0
        args_al = data.strip().split()[1:] if lower.startswith("alias ") else []
        if args_al:
            out("", done=True, exit_code=0)
        else:
            out("alias ll='ls -alF'\nalias la='ls -A'\nalias l='ls -CF'\n", done=True, exit_code=0)
    elif lower.startswith("unalias ") or lower == "unalias":
        # mock unalias: bare or with args — empty exit 0 (no real state)
        out("", done=True, exit_code=0)
    elif lower == "ulimit" or lower.startswith("ulimit "):
        # mock ulimit: bare/unlimited, -a prints fixed table, other args — unlimited
        if lower == "ulimit" or lower == "ulimit -a":
            out(
                "core file size          (blocks, -c) 0\n"
                "data seg size           (kbytes, -d) unlimited\n"
                "scheduling priority             (-e) 0\n"
                "file size               (blocks, -f) unlimited\n"
                "pending signals                 (-i) 30677\n"
                "max locked memory       (kbytes, -l) 65536\n"
                "max memory size         (kbytes, -m) unlimited\n"
                "open files                      (-n) 1048576\n"
                "pipe size            (512 bytes, -p) 8\n"
                "POSIX message queues     (bytes, -q) 819200\n"
                "real-time priority              (-r) 0\n"
                "stack size              (kbytes, -s) 8192\n"
                "cpu time               (seconds, -t) unlimited\n"
                "max user processes              (-u) 30677\n"
                "virtual memory          (kbytes, -v) unlimited\n"
                "file locks                      (-x) unlimited\n",
                done=True,
                exit_code=0,
            )
        else:
            out("unlimited\n", done=True, exit_code=0)
    elif lower == "finger" or lower.startswith("finger "):
        # mock finger: bare or with USER — fixed output
        out(
            "Login     Name       Tty      Idle  Login Time   Office\n"
            "mock      Mock User  pts/0          Jul 18 00:00\n",
            done=True,
            exit_code=0,
        )
    elif lower == "nologin" or lower.startswith("nologin "):
        # mock nologin: always prints denial, exit 1
        out("This account is currently not available.\n", done=True, exit_code=1)
    elif lower == "true" or lower.startswith("true "):
        # mock true: bare or with args — print nothing, exit 0
        out("", done=True, exit_code=0)
    elif lower == "false" or lower.startswith("false "):
        # mock false: bare or with args — print nothing, exit 1
        out("", done=True, exit_code=1)
    elif lower == "unset" or lower.startswith("unset "):
        # mock unset: bare or with args — print nothing, exit 0 (demo; no real state)
        out("", done=True, exit_code=0)

    elif lower.startswith("less ") or lower == "less":
        # mock less: with args — cat-like output of arg file; bare — stdin mock; exit 0
        arg = data.strip()[4:].strip() if lower.startswith("less") else ""
        if not arg:
            out("", done=True, exit_code=0)
        else:
            st_l = _session_state(sk)
            wd = st_l.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"less: {arg}: No such file\n", done=True, exit_code=1)
            else:
                content = node.get("content") or ""
                out(content if content.endswith("\n") or not content else content + "\n", done=True, exit_code=0)
    elif lower.startswith("more ") or lower == "more":
        # mock more: same as less — demo only, exit 0
        arg = data.strip()[4:].strip() if lower.startswith("more") else ""
        if not arg:
            out("", done=True, exit_code=0)
        else:
            st_m = _session_state(sk)
            wd = st_m.get("workdir") or "/workspace"
            if arg.startswith("/"):
                rel = arg.replace("/workspace", "").lstrip("/")
            else:
                base = wd.replace("/workspace", "").lstrip("/")
                rel = "/".join(p for p in (base + "/" + arg).split("/") if p and p != ".")
            node, cleaned = _ws_resolve(rel)
            if node is None or node.get("type") != "file":
                out(f"more: {arg}: No such file\n", done=True, exit_code=1)
            else:
                content = node.get("content") or ""
                out(content if content.endswith("\n") or not content else content + "\n", done=True, exit_code=0)
    elif lower.startswith("awk ") or lower == "awk":
        # mock awk: with args — print nothing, exit 0; bare — usage, exit 1
        arg = data.strip()[3:].strip() if lower.startswith("awk") else ""
        if not arg:
            out("awk: usage: awk 'PATTERN' FILE\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("sed ") or lower == "sed":
        # mock sed: with args — print nothing, exit 0; bare — usage, exit 1
        arg = data.strip()[3:].strip() if lower.startswith("sed") else ""
        if not arg:
            out("sed: usage: sed 's/old/new/' FILE\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)

    # --- file operations (demo only) ---
    elif lower == "cp" or lower == "cp ":
        out("cp: missing file operand\n", done=True, exit_code=1)
    elif lower == "mv" or lower == "mv ":
        out("mv: missing file operand\n", done=True, exit_code=1)
    elif lower == "rm" or lower == "rm ":
        out("rm: missing operand\n", done=True, exit_code=1)
    elif lower == "chmod" or lower == "chmod ":
        out("chmod: missing operand\n", done=True, exit_code=1)
    elif lower == "chown" or lower == "chown ":
        out("chown: missing operand\n", done=True, exit_code=1)
    elif lower == "chgrp" or lower == "chgrp ":
        out("chgrp: missing operand\n", done=True, exit_code=1)
    elif lower.startswith("kill ") or lower == "kill":
        if lower == "kill" or lower == "kill ":
            out("kill: usage: kill [-s sigspec | -n signum | -sigspec] pid | jobspec ... or kill -l [sigspec]\n", done=True, exit_code=1)
        else:
            pass  # demo: pretend success
    elif lower == "jobs" or lower.startswith("jobs "):
        out("[1]+ Stopped                 vim\n[2]- Running                 sleep 100 &\n", done=True, exit_code=0)
    elif lower.startswith("bg ") or lower == "bg":
        out("[1]+ sleep 100 &\n", done=True, exit_code=0)
    elif lower.startswith("fg ") or lower == "fg":
        out("[1]+ sleep 100\n", done=True, exit_code=0)


    elif lower == "bash" or lower.startswith("bash "):
        pass  # demo: no real shell
    elif lower == "sh" or lower.startswith("sh "):
        pass  # demo: no real shell
    elif lower.startswith("exit") or lower == "exit":
        out("exit\n", done=True, exit_code=0)
    elif lower == "logout" or lower.startswith("logout "):
        out("logout\n", done=True, exit_code=0)
    elif lower.startswith("source "):
        pass  # demo: no real sourcing
    elif lower == "set" or lower.startswith("set "):
        out("BASH=/bin/bash\nBASHOPTS=cmdhist:complete_fullquote\nHOME=/home/mock\nHOSTNAME=mock-host\nLANG=en_US.UTF-8\nPATH=/usr/local/bin:/usr/bin:/bin\nPWD=/home/mock\nSHELL=/bin/bash\nUSER=mock\n", done=True, exit_code=0)
    # --- archive/compression (demo only) ---
    elif lower.startswith("tar ") or lower == "tar":
        if lower == "tar" or data.strip() == "tar":
            out("tar: Cowardly refusing to create an empty archive\nTry 'tar --help' for more information.\n", done=True, exit_code=2)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("gzip ") or lower == "gzip":
        if lower == "gzip" or data.strip() == "gzip":
            out("gzip: compressed data not read from terminal\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("gunzip ") or lower == "gunzip":
        if lower == "gunzip" or data.strip() == "gunzip":
            out("gunzip: compressed data not read from terminal\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("zip ") or lower == "zip":
        if lower == "zip" or data.strip() == "zip":
            out("zip error: Nothing to do!\n", done=True, exit_code=12)
        else:
            out("", done=True, exit_code=0)
    elif lower.startswith("unzip ") or lower == "unzip":
        if lower == "unzip" or data.strip() == "unzip":
            out("unzip: missing archive name\n", done=True, exit_code=1)
        else:
            out("", done=True, exit_code=0)
    # --- network (demo only) ---
    elif lower.startswith("curl "):
        out("", done=True, exit_code=0)  # demo: no real HTTP
    elif lower.startswith("wget "):
        out("", done=True, exit_code=0)  # demo: no real download
    elif lower.startswith("ssh "):
        out("ssh: connect to host mock-host port 22: Connection refused\n", done=True, exit_code=255)
    elif lower.startswith("scp "):
        out("", done=True, exit_code=0)  # demo
    elif lower.startswith("rsync "):
        out("", done=True, exit_code=0)  # demo
    elif lower.startswith("ping ") or lower == "ping":
        if lower == "ping" or lower == "ping ":
            out("ping: usage error: Destination address required\n", done=True, exit_code=1)
        else:
            out("PING localhost (127.0.0.1) 56(84) bytes of data.\n64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.010 ms\n\n--- localhost ping statistics ---\n1 packets transmitted, 1 received, 0% packet loss\n", done=True, exit_code=0)


    # --- editors/multiplexers (demo only) ---
    elif lower.startswith("man ") or lower == "man":
        if lower == "man" or lower == "man ":
            out("What manual page do you want?\nFor example, try \'man man\'.\n", done=True, exit_code=1)
        else:
            out("No manual entry for " + data.strip().split()[-1] + "\n", done=True, exit_code=16)
    elif lower.startswith("info ") or lower == "info":
        if lower == "info" or lower == "info ":
            out("info: no menu item \'(dir)\' in node \'(dir)top\'.\n", done=True, exit_code=1)
        else:
            out("No menu item \'" + data.strip().split()[-1] + "\' in node \'(dir)top\'.\n", done=True, exit_code=1)
    elif lower.startswith("vi ") or lower == "vi":
        out("mock: vi: command not available in demo mode\n", done=True, exit_code=1)
    elif lower.startswith("nano ") or lower == "nano":
        out("mock: nano: command not available in demo mode\n", done=True, exit_code=1)
    elif lower.startswith("screen ") or lower == "screen":
        out("mock: screen: command not available in demo mode\n", done=True, exit_code=1)
    elif lower.startswith("tmux ") or lower == "tmux":
        out("mock: tmux: command not available in demo mode\n", done=True, exit_code=1)
    # --- filesystem/system (demo only) ---
    elif lower.startswith("mount ") or lower == "mount":
        if lower == "mount" or lower == "mount ":
            out("sysfs on /sys type sysfs (rw,nosuid,nodev,noexec)\nproc on /proc type proc (rw,nosuid,nodev,noexec)\n/dev/sda1 on / type ext4 (rw,relatime)\n", done=True, exit_code=0)
        else:
            pass
    elif lower.startswith("umount ") or lower == "umount":
        if lower == "umount" or lower == "umount ":
            out("umount: no mount point specified.\n", done=True, exit_code=1)
        else:
            pass
    elif lower.startswith("dd "):
        pass
    elif lower.startswith("service ") or lower == "service":
        if lower == "service" or lower == "service ":
            out("Usage: service < option > | --status-all | service name [ action | ... ]\n", done=True, exit_code=1)
        else:
            pass
    elif lower.startswith("systemctl ") or lower == "systemctl":
        if lower == "systemctl" or lower == "systemctl ":
            out("  UNIT                     LOAD   ACTIVE SUB    DESCRIPTION\n  -.mount                  loaded active mounted Root Mount\n  sshd.service             loaded active running OpenSSH server\n\nLOAD   = Reflects whether the unit definition was properly loaded.\nACTIVE = The high-level unit activation state\n", done=True, exit_code=0)
        else:
            pass
    elif lower.startswith("lsblk ") or lower == "lsblk":
        out("NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT\nsda      8:0    0   20G  0 disk\n\u2514\u2500sda1 8:1    0   20G  0 part /\n", done=True, exit_code=0)
    elif lower.startswith("fdisk ") or lower == "fdisk":
        if lower == "fdisk" or lower == "fdisk ":
            out("Usage: fdisk [options] <disk>\n", done=True, exit_code=1)
        else:
            pass
    # --- user/group management (demo only) ---
    elif lower.startswith("at ") or lower == "at":
        if lower == "at" or lower == "at ":
            out("at: missing operand\n", done=True, exit_code=1)
        else:
            pass
    elif lower.startswith("cron") or lower == "cron":
        out("mock: cron: command not available in demo mode\n", done=True, exit_code=1)
    elif lower.startswith("crontab ") or lower == "crontab":
        if lower == "crontab" or lower == "crontab ":
            out("crontab: usage error: file name or -l, -r, -e required.\n", done=True, exit_code=1)
        else:
            pass
    elif lower.startswith("useradd ") or lower == "useradd":
        if lower == "useradd" or lower == "useradd ":
            out("Usage: useradd [options] LOGIN\n", done=True, exit_code=2)
        else:
            pass
    elif lower.startswith("userdel ") or lower == "userdel":
        if lower == "userdel" or lower == "userdel ":
            out("Usage: userdel [options] LOGIN\n", done=True, exit_code=2)
        else:
            pass
    elif lower.startswith("usermod ") or lower == "usermod":
        if lower == "usermod" or lower == "usermod ":
            out("Usage: usermod [options] LOGIN\n", done=True, exit_code=2)
        else:
            pass
    elif lower.startswith("groupadd ") or lower == "groupadd":
        if lower == "groupadd" or lower == "groupadd ":
            out("Usage: groupadd [options] GROUP\n", done=True, exit_code=2)
        else:
            pass
    elif lower.startswith("groupdel ") or lower == "groupdel":
        if lower == "groupdel" or lower == "groupdel ":
            out("Usage: groupdel [options] GROUP\n", done=True, exit_code=2)
        else:
            pass
    elif lower.startswith("mail ") or lower == "mail":
        out("mock: mail: command not available in demo mode\n", done=True, exit_code=1)


    # --- shell builtins (demo only) ---
    elif lower.startswith("ip ") or lower == "ip":
        if lower == "ip" or lower == "ip ":
            out("Usage: ip [ OPTIONS ] OBJECT { COMMAND | help }\n", done=True, exit_code=0)
        elif "addr" in lower:
            out("1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536\n    inet 127.0.0.1/8 scope host lo\n2: eth0: <BROADCAST,MULTICAST,UP> mtu 1500\n    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0\n", done=True, exit_code=0)
        else:
            pass  # demo
    elif lower.startswith("netstat ") or lower == "netstat":
        if lower == "netstat" or lower == "netstat ":
            out("Active Internet connections (servers and established)\nProto Recv-Q Send-Q Local Address           Foreign Address         State\ntcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN\ntcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN\n", done=True, exit_code=0)
        else:
            pass  # demo
    elif lower.startswith("traceroute ") or lower == "traceroute":
        if lower == "traceroute" or lower == "traceroute ":
            out("traceroute: missing host operand\n", done=True, exit_code=1)
        else:
            out("traceroute to mock-host (127.0.0.1), 30 hops max, 60 byte packets\n 1  mock-host (127.0.0.1)  0.010 ms  0.005 ms  0.004 ms\n", done=True, exit_code=0)


    # --- system info (missing from help) ---
    elif lower == "df" or lower.startswith("df "):
        out("Filesystem     1K-blocks    Used Available Use% Mounted on\n/dev/sda1       20480000 8192000  12288000  41% /\ntmpfs             512000       0    512000   0% /dev/shm\n", done=True, exit_code=0)
    elif lower == "free" or lower.startswith("free "):
        out("              total        used        free      shared  buff/cache   available\nMem:        8192000     2048000     4096000      128000     2048000     5888000\nSwap:       2048000           0     2048000\n", done=True, exit_code=0)
    elif lower == "ps" or lower.startswith("ps "):
        out("  PID TTY          TIME CMD\n    1 pts/0    00:00:00 bash\n  100 pts/0    00:00:00 ps\n", done=True, exit_code=0)
    elif lower == "uptime" or lower.startswith("uptime "):
        out(" 14:00:00 up 7 days,  3:00,  1 user,  load average: 0.01, 0.02, 0.00\n", done=True, exit_code=0)


    elif lower.startswith("echo "):
        out(data.strip()[5:] + "\n", done=True, exit_code=0)
    elif lower in {"clear", "cls"}:
        ws_send_text(
            conn,
            json.dumps({"type": "terminal_clear", "session_key": sk, "stream_id": stream_id}),
        )
        out("", done=True, exit_code=0)
    elif lower in {"exit", "quit"}:
        out("logout\n", done=True, exit_code=0)
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "terminal_exit",
                    "session_key": sk,
                    "stream_id": stream_id,
                    "exit_code": 0,
                }
            ),
        )
    else:
        out(f"mock-sh: command not found: {data.strip()}\n", done=True, exit_code=127)


def _session_state(sk: str) -> Dict[str, Any]:
    st = SESSION_STATE.get(sk)
    if not st:
        st = {
            "mode": "default",
            "model": "mock-sonnet",
            "workdir": "/workspace",
            "project": "claude-code",
            "allow_all": False,
            "transcript": [],
        }
        SESSION_STATE[sk] = st
    return st


def _append_transcript(sk: str, role: str, content: str) -> None:
    st = _session_state(sk)
    st["transcript"].append({"role": role, "content": content[:4000]})
    if len(st["transcript"]) > 200:
        st["transcript"] = st["transcript"][-200:]


def _touch_session(sk: str, content: str = "", project: Optional[str] = None) -> None:
    st = _session_state(sk)
    if project:
        st["project"] = project
    with SESSIONS_LOCK:
        prev = SESSIONS.get(sk) or {}
        rec = {
            "id": sk,
            "session_key": sk,
            "project": project or prev.get("project") or st.get("project") or "claude-code",
            "title": prev.get("title") or "Session",
            "updated_at": time.time(),
            "last_user": (content[:200] if content else prev.get("last_user")),
            "mode": st["mode"],
            "model": st["model"],
            "workdir": st["workdir"],
            "running": False,
        }
        SESSIONS[sk] = rec
        for p in PROJECTS:
            p["sessions_count"] = sum(1 for s in SESSIONS.values() if s.get("project") == p["name"])


def _set_running(sk: str, running: bool) -> None:
    with SESSIONS_LOCK:
        if sk in SESSIONS:
            SESSIONS[sk]["running"] = running
            SESSIONS[sk]["updated_at"] = time.time()


def _handle_cancel(conn: socket.socket, msg: Dict[str, Any]) -> None:
    sk = msg.get("session_key") or ""
    ctx = msg.get("reply_ctx") or ""
    cancelled = False
    with ACTIVE_LOCK:
        keys = list(ACTIVE_RUNS.keys())
        for k in keys:
            if k == ctx or (not ctx and k.startswith(sk + "|")) or (ctx and k.endswith("|" + ctx)):
                ACTIVE_RUNS[k].set()
                cancelled = True
        if ctx in ACTIVE_RUNS:
            ACTIVE_RUNS[ctx].set()
            cancelled = True
    text = "run cancelled (mock)." if cancelled else "no active run to cancel (mock)."
    ws_send_text(
        conn,
        json.dumps(
            {
                "type": "run_done",
                "session_key": sk,
                "reply_ctx": ctx,
                "status": "cancelled" if cancelled else "idle",
                "content": text,
            },
            ensure_ascii=False,
        ),
    )
    if cancelled:
        _set_running(sk, False)
        _stream_reply(conn, sk, ctx or "cancel", text, cancellable=False)


def _handle_message(conn: socket.socket, msg: Dict[str, Any]) -> None:
    content = (msg.get("content") or "").strip()
    sk = msg.get("session_key") or "huan:unknown:unknown"
    ctx = msg.get("reply_ctx") or str(uuid.uuid4())
    images = msg.get("images") or []
    files = msg.get("files") or []
    project = _project_hint(content)
    with SESSIONS_LOCK:
        if sk in SESSIONS and SESSIONS[sk].get("project"):
            project = SESSIONS[sk]["project"]
    # session_key platform:scope:user may include project-ish scopes
    if ":hermes" in sk or sk.startswith("huanhermes-app:hermes"):
        project = "hermes"
    _touch_session(sk, content=content, project=project)
    attach_note = ""
    if images or files:
        attach_note = f" [attachments: {len(images)} image(s), {len(files)} file(s)]"
    _append_transcript(sk, "user", (content or "(attachment)") + attach_note)

    if content.lower() in ("/stop", "/cancel"):
        _handle_cancel(conn, {"session_key": sk, "reply_ctx": ctx})
        return

    if content.startswith("/perm") or content.lower() == "need permission":
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "buttons",
                    "session_key": sk,
                    "reply_ctx": ctx,
                    "content": "Mock agent wants to run: `echo hello` — allow?",
                    "buttons": [
                        [
                            {"text": "Allow", "data": "perm:demo:allow"},
                            {"text": "Deny", "data": "perm:demo:deny"},
                            {"text": "Allow all", "data": "perm:demo:allow_all"},
                        ]
                    ],
                }
            ),
        )
        return

    activity_push("chat.message", f"message in {sk}", session_key=sk, preview=(content or "")[:80])
    if content.startswith("/"):
        reply = _mock_slash(sk, content)
        _stream_reply(conn, sk, ctx, reply, cancellable=False)
        return

    st = _session_state(sk)
    st_project = st.get("project") or project
    if st_project == "hermes":
        st["model"] = st.get("model") if st.get("model") not in ("mock-sonnet",) else "mock-hermes"
        q = (content or "").strip()
        mem_hits = 0
        mem_preview = "(no query)"
        if q:
            # Fake memory.search over a tiny local store for protocol demos.
            store = [
                "user prefers concise ship notes",
                "app is console-only; agent loop stays on Host",
                "never embed tokens in pairing URI",
                "mock hermes project demonstrates ADR-002 shape",
            ]
            hits = [m for m in store if any(w in m.lower() for w in q.lower().split() if len(w) > 2)]
            mem_hits = len(hits)
            mem_preview = "; ".join(hits[:3]) if hits else "0 hits"
        reply = (
            f"[hermes-mock|model={st.get('model')}|mode={st.get('mode')}]\n"
            f"Hermes-shaped session (ADR-002). User said: {content or '(no text)'}\n"
            f"{attach_note.strip()}\n\n"
            "### Hermes mock\n"
            "- **memory.search** stub over in-process phrases\n"
            f"- hits={mem_hits}: `{mem_preview}`\n"
            "- skills: hermes-agent (readonly catalog)\n\n"
            "| Agent | Status |\n"
            "| --- | --- |\n"
            "| hermes | mock |\n"
            "| claude-code | mock |\n\n"
            "- [x] memory.search stub\n"
            "- [ ] ~~real process~~ still mock (Host adapter later)\n"
            "- [ ] system notifications\n\n"
            "Docs: [ADR-002](docs/adr/002-hermes-adapter.md)\n\n"
            "```dart\n"
            "final caps = ['stream','tools','cancel','memory'];\n"
            "// Host maps Bridge → real Hermes later\n"
            "```\n\n"
            "This is NOT a live Hermes process.\n"
            f"workdir={st.get('workdir')}"
        )
        # hermes-flavored tool name
        tool_name = "memory.search"
        tool_out = f"{mem_hits} memories · {mem_preview}"
    else:
        reply = (
            f"[mock:{st_project}|{st.get('model')}|mode={st.get('mode')}] 收到：{content or '(attachment)'}\n"
            f"{attach_note}\n\n"
            "### Mock markdown\n"
            "这是 **HuanHermes Mock Host** 的流式回复，用于验证控制台 Markdown 渲染。\n\n"
            "- 列表项 · 粗体 · `inline code`\n"
            "- 真连服务器时，此处将由 Claude Code / Codex / Hermes 产生\n\n"
            "```\n"
            f"workdir={st.get('workdir')}\n"
            "```\n"
            f"> workdir={st.get('workdir')}"
        )
        tool_name = "echo"
        tool_out = "ok"
    cancel_ev = threading.Event()
    run_key = f"{sk}|{ctx}"
    with ACTIVE_LOCK:
        ACTIVE_RUNS[run_key] = cancel_ev
        ACTIVE_RUNS[ctx] = cancel_ev
    _set_running(sk, True)

    ws_send_text(conn, json.dumps({"type": "typing_start", "session_key": sk, "reply_ctx": ctx}))
    time.sleep(0.03)
    ws_send_text(
        conn,
        json.dumps(
            {
                "type": "thinking",
                "session_key": sk,
                "reply_ctx": ctx,
                "content": "planning mock response…",
            },
            ensure_ascii=False,
        ),
    )
    time.sleep(0.03)
    ws_send_text(
        conn,
        json.dumps(
            {
                "type": "tool_call",
                "session_key": sk,
                "reply_ctx": ctx,
                "name": tool_name,
                "input": (content or attach_note)[:80],
            },
            ensure_ascii=False,
        ),
    )
    time.sleep(0.03)
    if not cancel_ev.is_set():
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "tool_result",
                    "session_key": sk,
                    "reply_ctx": ctx,
                    "name": tool_name,
                    "output": tool_out,
                },
                ensure_ascii=False,
            ),
        )

    cancelled = _stream_reply(conn, sk, ctx, reply, cancellable=True, cancel_ev=cancel_ev)
    ws_send_text(conn, json.dumps({"type": "typing_stop", "session_key": sk, "reply_ctx": ctx}))
    status = "cancelled" if cancelled else "completed"
    ws_send_text(
        conn,
        json.dumps({"type": "run_done", "session_key": sk, "reply_ctx": ctx, "status": status}),
    )
    _set_running(sk, False)
    with ACTIVE_LOCK:
        ACTIVE_RUNS.pop(run_key, None)
        ACTIVE_RUNS.pop(ctx, None)


def _project_hint(content: str) -> str:
    c = content.lower()
    if "codex" in c:
        return "codex"
    if "hermes" in c:
        return "hermes"
    return "claude-code"


def _mock_slash(sk: str, content: str) -> str:
    parts = content.split()
    cmd = parts[0].lower()
    st = _session_state(sk)
    if cmd in ("/help", "/h"):
        return "mock commands: /help /status /mode /model /dir /cd /stop /cancel /perm"
    if cmd == "/status":
        return (
            f"mock host uptime={int(time.time()-START_TS)}s projects={len(PROJECTS)} "
            f"mode={st['mode']} model={st['model']} dir={st['workdir']}"
        )
    if cmd == "/mode":
        if len(parts) > 1:
            st["mode"] = parts[1]
            _touch_session(sk)
            return f"mode set to: {st['mode']}"
        return f"current mode: {st['mode']} (options: default, plan, acceptEdits, bypassPermissions)"
    if cmd == "/model":
        if len(parts) > 1:
            st["model"] = parts[1]
            _touch_session(sk)
            return f"model set to: {st['model']}"
        return f"current model: {st['model']} (options: mock-sonnet, mock-codex, mock-hermes)"
    if cmd in ("/dir", "/cd"):
        if len(parts) > 1:
            path = parts[1]
            if not path.startswith("/"):
                return f"rejected path (must be absolute): {path}"
            st["workdir"] = path
            _touch_session(sk)
            return f"work_dir set to: {st['workdir']}"
        return f"work_dir: {st['workdir']}"
    if cmd in ("/stop", "/cancel"):
        return "use Bridge cancel or /stop while a run is active"
    return f"unknown command {cmd} (mock)"


def _stream_reply(
    conn: socket.socket,
    sk: str,
    ctx: str,
    text: str,
    *,
    cancellable: bool = True,
    cancel_ev: Optional[threading.Event] = None,
) -> bool:
    acc = ""
    step = max(1, len(text) // 12)
    cancelled = False
    for i in range(0, len(text), step):
        if cancellable and cancel_ev is not None and cancel_ev.is_set():
            cancelled = True
            break
        piece = text[i : i + step]
        acc += piece
        done = (i + step >= len(text)) and not cancelled
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "reply_stream",
                    "session_key": sk,
                    "reply_ctx": ctx,
                    "delta": piece,
                    "full_text": acc + ("…[cancelled]" if cancelled else ""),
                    "preview_handle": "",
                    "done": done or cancelled,
                },
                ensure_ascii=False,
            ),
        )
        time.sleep(0.04 if cancellable else 0.015)
    if cancelled:
        final = acc + "…[cancelled]"
        _append_transcript(sk, "assistant", final)
        ws_send_text(
            conn,
            json.dumps(
                {
                    "type": "reply",
                    "session_key": sk,
                    "reply_ctx": ctx,
                    "content": final,
                    "format": "markdown",
                },
                ensure_ascii=False,
            ),
        )
        return True
    _append_transcript(sk, "assistant", text)
    ws_send_text(
        conn,
        json.dumps(
            {
                "type": "reply",
                "session_key": sk,
                "reply_ctx": ctx,
                "content": text,
                "format": "markdown",
            },
            ensure_ascii=False,
        ),
    )
    return False


def _handle_card_action(conn: socket.socket, msg: Dict[str, Any]) -> None:
    action = msg.get("action") or ""
    sk = msg.get("session_key") or "huan:unknown"
    ctx = msg.get("reply_ctx") or str(uuid.uuid4())
    st = _session_state(sk)
    if action.endswith(":deny"):
        text = "Permission denied (mock)."
    elif action.endswith(":allow_all"):
        st["allow_all"] = True
        text = "allowed_all: mock will auto-approve subsequent tools in this session."
    else:
        text = "allowed: mock ran `echo hello` → hello"
    _stream_reply(conn, sk, ctx, text, cancellable=False)


def bridge_server() -> None:
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((BRIDGE_HOST, BRIDGE_PORT))
    srv.listen(50)
    log(f"Bridge WS listening on ws://{BRIDGE_HOST}:{BRIDGE_PORT}/bridge/ws")
    while True:
        conn, addr = srv.accept()
        t = threading.Thread(target=handle_bridge_client, args=(conn, addr), daemon=True)
        t.start()



def _create_session_rec(project: str, body: Dict[str, Any]) -> Dict[str, Any]:
    """Create session record (shared by flat + project-scoped POST)."""
    sid = (body.get("session_key") or body.get("id") or "").strip()
    if not sid:
        sid = f"huanhermes-app:mock:{uuid.uuid4().hex[:10]}"
    st = _session_state(sid)
    st["project"] = project
    if body.get("title"):
        title = body["title"]
    else:
        title = "New session"
    rec = {
        "id": body.get("id") or sid,
        "session_key": sid,
        "project": project,
        "title": title,
        "name": title,
        "updated_at": time.time(),
        "created_at": time.time(),
        "mode": st["mode"],
        "model": st["model"],
        "workdir": st["workdir"],
        "running": False,
        "live": False,
        "active": False,
        "platform": "bridge",
        "agent_type": next((p.get("agent_type") for p in PROJECTS if p["name"] == project), "claudecode"),
    }
    with SESSIONS_LOCK:
        SESSIONS[sid] = rec
        for p in PROJECTS:
            p["sessions_count"] = sum(1 for s in SESSIONS.values() if s.get("project") == p["name"])
    activity_push("session.create", f"session {sid}", project=project, title=title)
    host_log("info", f"session created {sid}", project=project, title=title)
    return rec


# ---------- Management HTTP ----------

class MgmtHandler(BaseHTTPRequestHandler):
    server_version = "HuanMockMgmt/0.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        log("mgmt " + (fmt % args))

    def _auth_ok(self) -> bool:
        auth = self.headers.get("Authorization") or ""
        if auth.startswith("Bearer ") and token_matches(auth[7:].strip(), MGMT_TOKEN):
            return True
        q = parse_qs(urlparse(self.path).query)
        if token_matches(q.get("token", [None])[0], MGMT_TOKEN):
            return True
        return False

    def _send(self, code: int, obj: Any) -> None:
        body = json_bytes(obj)
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if not self._auth_ok():
            self._send(401, {"ok": False, "error": "unauthorized: missing or invalid token"})
            return
        parsed = urlparse(self.path)
        path = parsed.path
        project = parse_qs(parsed.query).get("project", [None])[0]
        if path == "/api/v1/status":
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "version": "mock-0.1.198",
                        "uptime_seconds": int(time.time() - START_TS),
                        "connected_platforms": ["bridge"],
                        "projects_count": len(PROJECTS),
                        "sessions_count": len(SESSIONS),
                        "active_runs": len(ACTIVE_RUNS),
                        "capabilities": [
                            "sessions",
                            "workspace_readonly",
                            "skills",
                            "mcp",
                            "pairing",
                            "terminal",
                            "memory_readonly",
                            "cron_readonly",
                            "diff_readonly",
                            "activity_readonly",
                            "logs_readonly",
                            "agents_catalog",
                        ],
                        "hermes": {
                            "adapter": "mock",
                            "process": False,
                            "adr": "002",
                            "note": "Bridge shape only — real Hermes process is Host-side later",
                        },
                        "bridge_adapters": [
                            {
                                "platform": "huanhermes-app",
                                "project": "*",
                                "capabilities": ["text", "buttons", "typing", "preview", "terminal"],
                            },
                            {
                                "platform": "hermes-mock",
                                "project": "hermes",
                                "capabilities": ["text", "buttons", "tools", "memory", "cancel"],
                                "status": "mock",
                            },
                        ],
                    },
                },
            )
            return
        if path == "/api/v1/projects":
            self._send(200, {"ok": True, "data": {"projects": PROJECTS}})
            return
        m = re.match(r"^/api/v1/projects/([^/]+)$", path)
        if m:
            name = m.group(1)
            for p in PROJECTS:
                if p["name"] == name:
                    with SESSIONS_LOCK:
                        keys = [s["session_key"] for s in SESSIONS.values() if s.get("project") == name]
                    data = dict(p)
                    data["active_session_keys"] = keys
                    data["platforms"] = [{"type": "bridge", "connected": True}]
                    data["mode"] = "default"
                    self._send(200, {"ok": True, "data": data})
                    return
            self._send(404, {"ok": False, "error": "project not found"})
            return
        # project-scoped: /projects/{name}/sessions
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions$", path)
        if m:
            name = m.group(1)
            with SESSIONS_LOCK:
                items = [s for s in SESSIONS.values() if s.get("project") == name]
            self._send(200, {"ok": True, "data": {"sessions": items, "active_keys": {}}})
            return
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions/(.+)$", path)
        if m:
            name, sid = m.group(1), m.group(2)
            with SESSIONS_LOCK:
                rec = SESSIONS.get(sid)
            if not rec or rec.get("project") != name:
                self._send(404, {"ok": False, "error": "session not found"})
                return
            st = SESSION_STATE.get(sid) or {}
            data = dict(rec)
            data["transcript"] = list(st.get("transcript") or [])
            self._send(200, {"ok": True, "data": data})
            return
        if path == "/api/v1/agents" and project:
            selected = next((p for p in PROJECTS if p["name"] == project), None)
            if selected is not None:
                agent_type = selected.get("agent_type", project)
                self._send(200, {"ok": True, "data": {"agents": [{
                    "id": project, "name": project, "status": "mock",
                    "type": agent_type, "model": (selected.get("models") or [""])[0],
                    "provider": (selected.get("channels") or [""])[0],
                    "capabilities": selected.get("capabilities", []),
                }], "platforms": selected.get("platforms", [])}})
                return
        if path == "/api/v1/agents":
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "agents": [
                            {
                                "id": "claudecode",
                                "name": "Claude Code",
                                "status": "mock",
                                "type": "claude-code",
                                "model": "mock-sonnet",
                                "provider": "mock",
                                "version": "0.1-mock",
                                "capabilities": ["stream", "tools", "cancel", "workdir", "mode"],
                                "description": "Project-scoped coding agent (mock)",
                            },
                            {
                                "id": "codex",
                                "name": "Codex",
                                "status": "mock",
                                "type": "codex",
                                "model": "mock-codex",
                                "provider": "mock",
                                "version": "0.1-mock",
                                "capabilities": ["stream", "tools", "cancel"],
                                "description": "Codex-style agent (mock)",
                            },
                            {
                                "id": "hermes",
                                "name": "Hermes",
                                "status": "mock",
                                "type": "hermes",
                                "model": "mock-hermes",
                                "provider": "mock",
                                "version": "0.1-mock",
                                "adapter": "mock",
                                "process": False,
                                "capabilities": ["stream", "tools", "cancel", "memory", "skills", "mcp"],
                                "description": "Mock Hermes shape (ADR-002); Host maps Bridge → real process later",
                                "note": "Not a live Hermes agent loop",
                            },
                            {
                                "id": "cursor",
                                "name": "Cursor",
                                "status": "mock",
                            },
                            {
                                "id": "opencode",
                                "name": "OpenCode",
                                "status": "mock",
                            },
                        ],
                        "platforms": ["bridge", "telegram"],
                        "note": "Catalog only — App does not run agents locally",
                    },
                },
            )
            return
        if path == "/api/v1/bridge/adapters":
            self._send(200, {"ok": True, "data": {"adapters": []}})
            return
        if path == "/api/v1/mcp" and project in {"claude-code", "codex"}:
            names = (["claude-files", "claude-git"] if project == "claude-code"
                     else ["codex-files", "codex-git"])
            self._send(200, {"ok": True, "data": {"servers": [
                {"name": name, "status": "mock", "kind": "stdio",
                 "enabled": True, "tools": ["read", "list"],
                 "description": f"{project} project MCP (readonly mock)"} for name in names
            ]}})
            return
        if path == "/api/v1/mcp":
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "servers": [
                            {
                                "name": "filesystem",
                                "status": "mock",
                                "kind": "stdio",
                                "enabled": True,
                                "tools": ["read_file", "list_dir"],
                                "description": "Readonly MCP catalog demo",
                            },
                            {
                                "name": "git",
                                "status": "mock",
                                "kind": "stdio",
                                "enabled": True,
                                "tools": ["status", "log"],
                                "description": "Readonly MCP catalog demo",
                            },
                            {
                                "name": "hermes-memory",
                                "status": "mock",
                                "kind": "inprocess",
                                "enabled": True,
                                "tools": ["memory.search", "memory.list"],
                                "description": "Mock Hermes memory tools (ADR-002 shape · not live process)",
                                "note": "Host maps to real Hermes memory later",
                            },
                            {
                                "name": "hermes-skills",
                                "status": "mock",
                                "kind": "inprocess",
                                "enabled": True,
                                "tools": ["skills.list", "skills.view"],
                                "description": "Readonly skills catalog surface for Hermes project",
                            },
                            {
                                "name": "offline-demo",
                                "status": "disabled",
                                "kind": "stdio",
                                "enabled": False,
                                "tools": [],
                                "description": "Sample disabled MCP server (catalog only)",
                                "note": "Not started by App",
                            },
                        ]
                    },
                },
            )
            return
        if path == "/api/v1/skills" and project in {"claude-code", "codex"}:
            prefix = "Claude" if project == "claude-code" else "Codex"
            names = (["claude-code-review", "anthropic-tools", "prompt-cache"]
                     if project == "claude-code" else ["codex-cli", "openai-tools", "patch-review"])
            self._send(200, {"ok": True, "data": {"skills": [
                {"name": name, "description": f"{prefix} project skill (readonly mock)",
                 "source": project, "category": "agent", "version": "0.1-mock",
                 "tags": [project, "agent"]} for name in names
            ]}})
            return
        if path == "/api/v1/skills":
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "skills": [
                            {
                                "name": "hermes-agent",
                                "description": "Configure Hermes Agent (readonly mock)",
                                "source": "mock",
                                "category": "autonomous-ai-agents",
                                "version": "0.1-mock",
                                "tags": ["hermes", "console"],
                            },
                            {
                                "name": "github-pr-workflow",
                                "description": "PR lifecycle helpers (readonly mock)",
                                "source": "mock",
                                "category": "github",
                                "version": "0.1-mock",
                                "tags": ["git", "pr"],
                            },
                            {
                                "name": "systematic-debugging",
                                "description": "4-phase debugging checklist (readonly mock)",
                                "source": "mock",
                                "category": "software-development",
                                "version": "0.1-mock",
                                "tags": ["debug"],
                            },
                            {
                                "name": "writing-plans",
                                "description": "Implementation plans (readonly mock)",
                                "source": "mock",
                                "category": "software-development",
                                "version": "0.1-mock",
                                "tags": ["plan"],
                            },
                            {
                                "name": "memory-management",
                                "description": "Long-term memory prefs (readonly mock · ADR-002 shape)",
                                "source": "mock",
                                "category": "memory-management",
                                "version": "0.1-mock",
                                "tags": ["hermes", "memory"],
                            },
                        ]
                    },
                },
            )
            return
        if path == "/api/v1/pairing":
            # Device pairing payload for QR/text share (no secrets in repo defaults)
            token_hint = "use-app-stored-tokens"
            self._send(
                200,
                {
                    "ok": True,
                    "data": {
                        "scheme": "huanhermes",
                        "version": 1,
                        "host": BRIDGE_HOST if BRIDGE_HOST != "0.0.0.0" else "127.0.0.1",
                        "bridge_port": BRIDGE_PORT,
                        "mgmt_port": MGMT_PORT,
                        "use_tls": False,
                        "note": "Fill tokens on device; Host does not return live secrets here",
                        "pairing_code": f"huanhermes://connect?host=127.0.0.1&bridge={BRIDGE_PORT}&mgmt={MGMT_PORT}&tls=0",
                    },
                },
            )
            return
        if path == "/api/v1/workspace" or path == "/api/v1/workspace/":
            qs = parse_qs(urlparse(self.path).query)
            p = (qs.get("path") or [""])[0]
            data = workspace_list(p)
            if data.get("error"):
                self._send(404, {"ok": False, "error": data["error"], "path": p})
            else:
                self._send(200, {"ok": True, "data": data})
            return
        if path == "/api/v1/workspace/git":
            self._send(200, {"ok": True, "data": workspace_git_status()})
            return
        if path == "/api/v1/memory":
            q = parse_qs(urlparse(self.path).query)
            memory_project = (q.get("project") or [None])[0]
            scope = (q.get("scope") or [None])[0]
            qtext = ((q.get("q") or [""])[0] or "").lower()
            items = list(MEMORY_ENTRIES)
            if memory_project:
                items = [
                    item for item in items
                    if item.get("scope") == "global" or item.get("project") == memory_project
                ]
            if scope:
                items = [m for m in items if m.get("scope") == scope]
            if qtext:
                items = [
                    m
                    for m in items
                    if qtext in (m.get("title") or "").lower()
                    or qtext in (m.get("content") or "").lower()
                    or qtext in " ".join(m.get("tags") or []).lower()
                ]
            self._send(200, {"ok": True, "data": {"memories": items, "count": len(items)}})
            return
        m = re.match(r"^/api/v1/memory/([^/]+)$", path)
        if m:
            mid = m.group(1)
            for ent in MEMORY_ENTRIES:
                if ent.get("id") == mid:
                    self._send(200, {"ok": True, "data": ent})
                    return
            self._send(404, {"ok": False, "error": "memory not found"})
            return

        if path == "/api/v1/logs":
            qs = parse_qs(urlparse(self.path).query)
            try:
                limit = int((qs.get("limit") or ["80"])[0])
            except ValueError:
                limit = 80
            limit = max(1, min(limit, 200))
            level = ((qs.get("level") or [""])[0] or "").lower()
            source = ((qs.get("source") or [""])[0] or "").lower()
            with HOST_LOGS_LOCK:
                items = list(HOST_LOGS)
            if level:
                items = [x for x in items if str(x.get("level", "")).lower() == level]
            if source:
                items = [
                    x
                    for x in items
                    if source in str(x.get("source") or x.get("logger") or x.get("component") or "").lower()
                ]
            items = items[-limit:]
            items = list(reversed(items))
            self._send(200, {"ok": True, "data": {"logs": items, "count": len(items)}})
            return
        if path == "/api/v1/activity":
            qs = parse_qs(urlparse(self.path).query)
            try:
                lim = int((qs.get("limit") or ["50"])[0])
            except ValueError:
                lim = 50
            self._send(200, {"ok": True, "data": {"events": activity_list(lim)}})
            return
        if path == "/api/v1/cron":
            self._send(200, {"ok": True, "data": {"jobs": CRON_JOBS}})
            return
        m = re.match(r"^/api/v1/cron/([^/]+)$", path)
        if m:
            jid = m.group(1)
            for job in CRON_JOBS:
                if job.get("id") == jid:
                    self._send(200, {"ok": True, "data": job})
                    return
            self._send(404, {"ok": False, "error": "cron job not found"})
            return
        if path == "/api/v1/workspace/diff":
            qs = parse_qs(urlparse(self.path).query)
            p = (qs.get("path") or [""])[0]
            self._send(200, {"ok": True, "data": workspace_diff(p)})
            return
        if path == "/api/v1/sessions":
            q = parse_qs(urlparse(self.path).query)
            project = q.get("project", [None])[0]
            with SESSIONS_LOCK:
                items = list(SESSIONS.values())
            if project:
                items = [s for s in items if s.get("project") == project]
            self._send(200, {"ok": True, "data": {"sessions": items}})
            return
        m = re.match(r"^/api/v1/sessions/(.+)$", path)
        if m:
            sid = m.group(1)
            with SESSIONS_LOCK:
                rec = SESSIONS.get(sid)
            if not rec:
                self._send(404, {"ok": False, "error": "session not found"})
                return
            st = SESSION_STATE.get(sid) or {}
            data = dict(rec)
            data["transcript"] = list(st.get("transcript") or [])
            data["mode"] = st.get("mode", rec.get("mode"))
            data["model"] = st.get("model", rec.get("model"))
            data["workdir"] = st.get("workdir", rec.get("workdir"))
            self._send(200, {"ok": True, "data": data})
            return
        self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._auth_ok():
            self._send(401, {"ok": False, "error": "unauthorized: missing or invalid token"})
            return
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, {"ok": False, "error": "invalid json"})
            return
        # Flat MVP: POST /sessions
        if path == "/api/v1/sessions":
            project = body.get("project") or "claude-code"
            rec = _create_session_rec(project, body)
            self._send(200, {"ok": True, "data": rec})
            return
        # project-scoped POST /projects/{name}/sessions  (session_key optional; generated if missing)
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions$", path)
        if m:
            project = m.group(1)
            rec = _create_session_rec(project, body)
            self._send(200, {"ok": True, "data": rec})
            return
        self._send(404, {"ok": False, "error": "not found"})

    def do_PATCH(self) -> None:  # noqa: N802
        if not self._auth_ok():
            self._send(401, {"ok": False, "error": "unauthorized: missing or invalid token"})
            return
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, {"ok": False, "error": "invalid json"})
            return
        m = re.match(r"^/api/v1/sessions/(.+)$", path)
        proj_m = re.match(r"^/api/v1/projects/([^/]+)/sessions/(.+)$", path)
        sid = None
        if m:
            sid = m.group(1)
        elif proj_m:
            sid = proj_m.group(2)
        if sid:
            title = body.get("title") or body.get("name")
            if not title or not str(title).strip():
                self._send(400, {"ok": False, "error": "title required"})
                return
            title = str(title).strip()
            with SESSIONS_LOCK:
                rec = SESSIONS.get(sid)
                if not rec:
                    self._send(404, {"ok": False, "error": "session not found"})
                    return
                rec["title"] = title
                rec["name"] = title
                rec["updated_at"] = int(time.time())
                SESSIONS[sid] = rec
                out = dict(rec)
            activity_push("session.rename", f"renamed {sid}", session_id=sid, title=title)
            host_log("info", f"session renamed {sid} -> {title}", session_id=sid)
            self._send(200, {"ok": True, "data": out})
            return
        self._send(404, {"ok": False, "error": "not found"})


    def do_DELETE(self) -> None:  # noqa: N802
        if not self._auth_ok():
            self._send(401, {"ok": False, "error": "unauthorized: missing or invalid token"})
            return
        path = urlparse(self.path).path
        m = re.match(r"^/api/v1/sessions/(.+)$", path)
        if m:
            sid = m.group(1)
            with SESSIONS_LOCK:
                SESSIONS.pop(sid, None)
            SESSION_STATE.pop(sid, None)
            self._send(200, {"ok": True, "data": {"deleted": sid}})
            return
        m = re.match(r"^/api/v1/projects/([^/]+)/sessions/(.+)$", path)
        if m:
            _name, sid = m.group(1), m.group(2)
            with SESSIONS_LOCK:
                SESSIONS.pop(sid, None)
            SESSION_STATE.pop(sid, None)
            self._send(200, {"ok": True, "data": {"deleted": sid}})
            return
        self._send(404, {"ok": False, "error": "not found"})


def mgmt_server() -> None:
    httpd = ThreadingHTTPServer((BRIDGE_HOST, MGMT_PORT), MgmtHandler)
    log(f"Management HTTP listening on http://{BRIDGE_HOST}:{MGMT_PORT}/api/v1")
    httpd.serve_forever()


def main() -> None:
    activity_push("host.start", "Mock Host started", bridge=BRIDGE_PORT, mgmt=MGMT_PORT)
    host_log("info", "Mock Host started", bridge=BRIDGE_PORT, mgmt=MGMT_PORT)
    host_log("info", "Management HTTP ready")
    host_log("debug", "Seed demo log lines for console")
    log("starting HuanHermes Mock Host")
    log(f"BRIDGE_TOKEN set (len={len(BRIDGE_TOKEN)}) MGMT_TOKEN set (len={len(MGMT_TOKEN)})")
    t = threading.Thread(target=mgmt_server, name="mgmt", daemon=True)
    t.start()
    bridge_server()


if __name__ == "__main__":
    main()
