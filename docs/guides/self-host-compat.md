# 自研 Host 兼容层

目标：任何实现 **本仓 Bridge + Mgmt 子集** 的 Host，均可被 HuanHermes App 使用。

参考实现：`server/mock-host/mock_host.py`。

## Bridge WS

路径示例：`ws://host:bridge/bridge/ws?token=...`

| 方向 | type |
|------|------|
| App→Host | `register`, `message`, `cancel`, `card_action`, `ping`, `preview_ack`, `terminal_input`, `terminal_resize` |
| Host→App | `register_ack`, `reply_stream`/`reply`, `thinking`, `tool_*`, `buttons`/`card`, `run_done`, `typing_*`, `terminal_out`, `terminal_clear`, `terminal_exit` |

`message` 可带 `images[]` / `files[]`（可选）。  
`terminal_*` 为轻量终端通道（可选；非完整 PTY 亦可）。

## Management REST

前缀：`/api/v1`，鉴权 `Authorization: Bearer <mgmt_token>`。

| Method | Path |
|--------|------|
| GET | `/status` |
| GET | `/projects` （可选 `capabilities[]`） |
| GET/POST/DELETE | `/sessions` **或** `/projects/{name}/sessions` |
| GET | `/sessions/{id}` 或 project 作用域 detail |
| GET | `/skills`（可选） |
| GET | `/mcp`（可选只读目录） |
| GET | `/pairing`（可选，**禁止返回 token**） |

## Hermes

Host 侧将 Hermes 映射为 `agent_type=hermes` 的 project（ADR-002）。App 不跑 Hermes 进程。

## 禁止

- 把「安装外部宿主」写成唯一路径  
- 协议扩展不写文档就进代码  
- 修改用户已有渠道/密钥配置
