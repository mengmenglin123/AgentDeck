# Bridge 协议子集（HuanHermes 兼容）

> 目标：与 [cc-connect Bridge Protocol](https://github.com/chenhg5/cc-connect/blob/main/docs/bridge-protocol.md) **子集兼容**，便于 Phase 1 直连上游。

## 连接

```text
ws://<host>:<port>/bridge/ws?token=<BRIDGE_TOKEN>
# 或 Header: Authorization: Bearer <token>
# 或 Header: X-Bridge-Token: <token>
```

默认开发端口：`9810`。生产必须使用 **WSS**。

## 客户端 → Host

| type | 必填字段 | 说明 |
|------|----------|------|
| `register` | `platform`, `capabilities` | 连接后第一条；`platform` 建议 `huanhermes-app` |
| `message` | `msg_id`, `session_key`, `user_id`, `content`, `reply_ctx` | 用户消息 |
| `card_action` | `session_key`, `action`, `reply_ctx` | 权限按钮等 |
| `ping` | `ts` | 心跳（建议 30s） |

### capabilities（MVP）

`text`, `buttons`, `typing`, `preview`（流式时声明）

### session_key

建议：`huan:{device_id}:{conversation_id}`  
（与上游 `{platform}:{scope}:{user}` 模式兼容。）

## Host → 客户端

| type | 说明 |
|------|------|
| `register_ack` | `{ ok, error }` |
| `reply` | 完整回复 `{ content, format?, session_key, reply_ctx }` |
| `reply_stream` | 流式 `{ delta, full_text, done, preview_handle? }` |
| `buttons` | 权限等 `{ content, buttons[][] }` |
| `typing_start` / `typing_stop` | 输入指示 |
| `pong` | 心跳响应 |

## 权限动作（约定）

按钮 `data` / `action` 推荐：

- `perm:{request_id}:allow`
- `perm:{request_id}:deny`
- `perm:{request_id}:allow_all`

App 点选后发 `card_action` 或把 action 作为 `message.content`（Mock 两者皆可）。

## 非目标（本子集）

卡片完整 Schema、音频、文件大对象、预览 handle 全链路 —— 后续版本再加。
