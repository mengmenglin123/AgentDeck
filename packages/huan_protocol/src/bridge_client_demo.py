"""Demo: connect to mock/real Bridge and send one message."""

from __future__ import annotations

import json
import sys
import threading
import time

# allow running as python3 -m src.bridge_client_demo from package root
if __name__ == "__main__" and __package__ is None:
    sys.path.insert(0, ".")

from src.bridge_client import BridgeClient
from src.models import ConnectionConfig, TranscriptReducer


def main() -> None:
    cfg = ConnectionConfig()
    reducer = TranscriptReducer()
    done = threading.Event()

    def on_msg(payload: dict) -> None:
        print("[host]", json.dumps(payload, ensure_ascii=False))
        reducer.apply_bridge_payload(payload)
        if payload.get("type") in ("reply",) or (
            payload.get("type") == "reply_stream" and payload.get("done")
        ):
            done.set()

    def on_err(exc: Exception) -> None:
        print("[error]", type(exc).__name__, exc)
        done.set()

    client = BridgeClient(cfg, on_message=on_msg, on_error=on_err)
    print("connecting to", cfg.host, cfg.bridge_port, "…")
    client.connect()
    print("registered; sending hello")
    client.send_user_message("hello from huan_protocol demo", conversation_id="demo-1")
    done.wait(timeout=15)
    print("--- transcript ---")
    for m in reducer.messages:
        print(f"{m.role}: {m.content[:200]}")
    client.close()


if __name__ == "__main__":
    main()
