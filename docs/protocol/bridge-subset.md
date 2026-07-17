# Bridge 协议子集（HuanHermes 拥有）

规范源：**本文件**。实现：`server/mock-host`、App `BridgeClient`、Python `packages/huan_protocol`。

## 连接

`ws(s)://host:port/bridge/ws?token=<bridge_token>`

## 核心消息

### register / register_ack

App 注册 platform + capabilities（`text`, `buttons`, `typing`, `preview`…）。

### message

```json
{
  "type": "message",
  "msg_id": "...",
  "session_key": "...",
  "user_id": "user",
  "user_name": "User",
  "content": "hello",
  "reply_ctx": "...",
  "images": [],
  "files": [],
  "audio": null
}
```

### cancel / card_action / ping

见 Mock 与客户端实现。

### terminal_input / terminal_resize（轻量终端通道）

App → Host：

```json
{ "type": "terminal_input", "session_key": "...", "stream_id": "term-1", "data": "ls" }
{ "type": "terminal_resize", "session_key": "...", "cols": 80, "rows": 24 }
```

Host → App：

```json
{ "type": "terminal_out", "session_key": "...", "stream_id": "term-1", "data": "$ ls\n", "done": false }
{ "type": "terminal_out", "session_key": "...", "stream_id": "term-1", "data": "README.md\n", "done": true, "exit_code": 0 }
{ "type": "terminal_clear", "session_key": "...", "stream_id": "term-1" }
{ "type": "terminal_exit", "session_key": "...", "stream_id": "term-1", "exit_code": 0 }
```

这是 **协议演示级** 通道；真 Host 可映射到 PTY。Mock 仅回显内置命令（`help`/`pwd`/`ls`/`echo`…）。

### Host → App 事件

`reply_stream`, `reply`, `thinking`, `tool_call`, `tool_result`, `buttons`, `card`, `run_done`, `typing_start`, `typing_stop`, `preview_start`, `update_message`, `terminal_out`, `terminal_clear`, `terminal_exit`, `terminal_ack`。

## Slash 快捷（可选）

App 工具栏可发送 `/mode` `/model` `/dir` `/status` `/stop` 等；Host 自行解释。

## Attachments（可选）

`images` / `files` 元素可含 `name`, `mime`, `data_base64`。Host 可忽略；Mock 会回显数量。
