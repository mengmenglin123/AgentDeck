# huan_protocol (Python reference)

Bridge WebSocket client、Management REST client、TranscriptReducer。

```bash
# from repo root — start mock first
python3 server/mock-host/mock_host.py

# tests
cd packages/huan_protocol
python3 -m test.test_bridge_client

# demo
python3 -m src.bridge_client_demo
```

后续 Flutter 客户端可对照 `src/models.py` 字段移植。
