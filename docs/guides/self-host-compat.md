# 自研 Host 兼容层（P2-8）

目标：任何实现 **本仓 Bridge + Mgmt 子集** 的 Host，均可被 HuanHermes App 当控制台使用。  
**不要求** 使用或修改现有 cc-connect 部署。

## 必须实现

### Bridge WS `ws://host:bridge/bridge/ws?token=...`

| 方向 | type | 说明 |
|------|------|------|
| App→Host | `register` | platform + capabilities |
| Host→App | `register_ack` | `{ok:true}` |
| App→Host | `message` | content, session_key, reply_ctx, images[], files[] |
| App→Host | `cancel` | session_key, reply_ctx |
| App→Host | `card_action` | permission allow/deny/allow_all |
| App→Host | `ping` | |
| Host→App | `reply_stream` / `reply` | 流式或整包 |
| Host→App | `thinking` / `tool_call` / `tool_result` | 可选 |
| Host→App | `buttons` / `card` | 权限 UI |
| Host→App | `run_done` | 结束 run |
| Host→App | `typing_start` / `typing_stop` | 可选 |

### Management REST `http://host:mgmt/api/v1`

鉴权：`Authorization: Bearer <mgmt_token>`。

| Method | Path | 说明 |
|--------|------|------|
| GET | `/status` | version 等 |
| GET | `/projects` | 含 `agent_type`、可选 `capabilities[]` |
| GET/POST/DELETE | `/sessions` **或** `/projects/{name}/sessions` | 双方言，App 自动探测 |
| GET | `/sessions/{id}` | transcript 可选 |
| GET | `/skills` | 可选只读 |
| GET | `/pairing` | 可选，**不要返回 token** |

## Hermes

见 [ADR-002](../adr/002-hermes-adapter.md)：Host 侧把 Hermes 进程映射为 `agent_type=hermes` 的 project；App 不跑 agent loop。

## 参考实现

本仓 `server/mock-host/mock_host.py` 是可运行的兼容子集（开发用）。

## 禁止

- 为联调修改用户已部署 Host 的 provider / 代理 / API key  
- 在协议文档外偷偷依赖私有字段（扩展字段须先写 `docs/protocol`）
