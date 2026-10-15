#!/usr/bin/env python3
"""Tiny loopback SSH server for the dartssh2 adapter e2e test (needs paramiko).

Password auth (user "u" / "pw"), exec channels answered from a fixed table,
SFTP open/write/close into an in-memory store that later exec calls can
report on. Prints "PORT <n>" and "FP SHA256:<b64>" on stdout once listening.
"""
import base64
import hashlib
import socket
import sys
import threading

import paramiko

UPLOADS = {}


class Server(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL if (username, password) == ("u", "pw") else paramiko.AUTH_FAILED

    def get_allowed_auths(self, username):
        return "password"

    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_SUCCEEDED if kind == "session" else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_exec_request(self, channel, command):
        cmd = command.decode("utf-8", "replace")
        threading.Thread(target=_exec, args=(channel, cmd), daemon=True).start()
        return True


def _exec(channel, cmd):
    # Reply only after paramiko has acknowledged the exec request, like sshd.

    import time
    time.sleep(0.1)
    try:
        if "HH_DISCOVERY" in cmd:
            channel.sendall(b"HH_DISCOVERY\t1\nHH_AGENT\tcodex\t/usr/bin/codex\tcodex-cli 1.0\n")
            channel.sendall_stderr(b"motd noise\n")
            code = 0
        elif "curl --fail" in cmd:
            code = 42  # no curl/wget: force the SFTP fallback
        elif "companion_installer.py" in cmd:
            sizes = {k: len(v) for k, v in UPLOADS.items()}
            ok = any(k in cmd for k in sizes)
            if ok:
                channel.sendall(
                    b'HH_COMPANION\t{"version":"0.1.204","release_dir":"/r","service_path":"/s",'
                    b'"config_path":"/c/host.toml","activated":true,"service_started":false}\n'
                )
                code = 0
            else:
                channel.sendall_stderr(b"archive missing\n")
                code = 1
        else:
            channel.sendall_stderr(b"unknown command\n")
            code = 127
        channel.send_exit_status(code)
    finally:
        channel.close()


class Handle(paramiko.SFTPHandle):
    def __init__(self, path):
        super().__init__()
        self.path = path
        UPLOADS[path] = b""

    def write(self, offset, data):
        buf = UPLOADS[self.path]
        UPLOADS[self.path] = buf[:offset] + data + buf[offset + len(data):]
        return paramiko.SFTP_OK

    def close(self):
        return paramiko.SFTP_OK


class Sftp(paramiko.SFTPServerInterface):
    def open(self, path, flags, attr):
        return Handle(path)


def serve(sock, key):
    while True:
        conn, _ = sock.accept()
        t = paramiko.Transport(conn)
        t.add_server_key(key)
        t.set_subsystem_handler("sftp", paramiko.SFTPServer, Sftp)
        try:
            t.start_server(server=Server())
        except Exception:
            continue


def main():
    key = paramiko.Ed25519Key.from_private_key_file(sys.argv[1]) if len(sys.argv) > 1 else None
    if key is None:
        key = paramiko.RSAKey.generate(2048)
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(8)
    fp = base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip("=")
    print(f"PORT {sock.getsockname()[1]}", flush=True)
    print(f"FP SHA256:{fp}", flush=True)
    serve(sock, key)


if __name__ == "__main__":
    main()
