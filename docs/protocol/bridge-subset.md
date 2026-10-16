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
  "project": "codex",
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

权限卡片由 Host 生成。Agent 的原始按钮 ID 不可信；Host 生成短期一次性的
`permission_id`，按钮数据固定为 `perm:<permission_id>:allow`、
`perm:<permission_id>:allow_all`、`perm:<permission_id>:deny`。App 发送
`card_action` 时，Host 必须校验 session、reply context、TTL 和一次性消费。
拒绝时返回 `error_code="permission_action_rejected"`，不得转发给 Agent。
prompt 和审计记录必须脱敏，token 不得进入日志、通知或公开剪贴板。
生产 Host 应将权限审计接入本地私有存储；审计写入失败时不得消费待处理权限，
也不得在未记录审计的情况下向 Agent 放行决定。

### 小附件约束

`images[]` / `files[]` 可携带 `name`, `mime`, `size_bytes`, `data_base64`。App 侧当前限制：

- 单个附件最多 5 MB
- 单条消息附件总计最多 10 MB
- 最多 4 个附件
- 带附件消息发送失败时不写入离线队列

这是小附件兼容路径；更大文件必须另行定义分片或对象存储协议。

### terminal_open / terminal_input / terminal_resize / terminal_close（轻量终端通道）

App → Host：

```json
{ "type": "terminal_open", "session_key": "...", "project": "codex", "stream_id": "term-1", "cols": 80, "rows": 24 }
{ "type": "terminal_input", "session_key": "...", "project": "codex", "stream_id": "term-1", "data": "ls" }
{ "type": "terminal_resize", "session_key": "...", "project": "codex", "stream_id": "term-1", "cols": 80, "rows": 24 }
{ "type": "terminal_close", "session_key": "...", "project": "codex", "stream_id": "term-1" }
{ "type": "terminal_permission_action", "session_key": "...", "project": "codex", "stream_id": "term-1", "action": "perm:<id>:allow" }
```

Host → App：

```json
{ "type": "terminal_open_ack", "session_key": "...", "stream_id": "term-1", "ok": true, "cols": 80, "rows": 24 }
{ "type": "terminal_out", "session_key": "...", "stream_id": "term-1", "data": "$ ls\n", "done": false }
{ "type": "terminal_out", "session_key": "...", "stream_id": "term-1", "data": "README.md\n", "done": true, "exit_code": 0 }
{ "type": "terminal_clear", "session_key": "...", "stream_id": "term-1" }
{ "type": "terminal_exit", "session_key": "...", "stream_id": "term-1", "exit_code": 0 }
{ "type": "terminal_permission", "session_key": "...", "stream_id": "term-1", "permission_id": "...", "scope": "terminal.open", "content": "Allow opening a terminal?", "buttons": [[{"text":"Allow","data":"perm:<id>:allow"}]] }
```

`done` 语义：每次 `terminal_input` 之后，Host 在输出静默（生产 Host 默认 0.25s 无新输出）或进程退出时发送**恰好一条** `done: true` 的 `terminal_out`（可为空 `data`；进程退出时附 `exit_code`）。未发送输入时不发 `done`。客户端不应只依赖 `done` 解除忙碌：收到本 stream 任意 `terminal_out` 即可解除，并保留约 10s 兜底。

这是 **协议演示级** 通道；真 Host 可映射到 PTY。Mock 回显内置命令（`help`/`pwd`/`ls`/`whoami`/`uname`/`hostname`/`id`/`date`/`env`/`cat`/`echo`/`stty size`…），并记住最近一次 `terminal_resize` 的 `cols`/`rows`。App 根据布局估算几何后推送 resize（非真 ioctl）。

App 端只保留有上限的本地输出窗口；该窗口不是 Host 审计或完整 transcript，超出上限时丢弃最旧显示内容并保留最新输出。

客户端断线重连时必须重新注册并生成新的 `stream_id`；不得复用无法确认仍归属当前连接的旧 terminal stream。重连次数和退避由客户端策略限制，不能无限重连。

客户端可将连续的 `terminal_out` 帧合并后再刷新显示；合并队列必须有上限，不能因为 Host 高频输出而无限积压。协议帧的顺序和内容仍以 Host 发送顺序为准。

### Host → App 事件

`reply_stream`, `reply`, `thinking`, `tool_call`, `tool_result`, `buttons`, `card`, `run_done`, `typing_start`, `typing_stop`, `preview_start`, `update_message`, `terminal_permission`, `terminal_out`, `terminal_clear`, `terminal_exit`, `terminal_ack`。

生产 PTY Host 可在 `terminal_open` 前发送 `terminal_permission`。该权限必须由 Host
生成并通过 PermissionGate 绑定当前 `session_key` 与 `stream_id`；App 只能回传
`terminal_permission_action`，不能提交任意 permission id。Host 在收到 `allow` 或
`allow_all` 前不得启动 PTY，`deny`、过期、错误上下文和审计写入失败都必须保持
PTY 未启动。权限请求与决定写入脱敏审计记录。

## Slash 快捷（可选）

App 工具栏可发送 `/mode` `/model` `/dir` `/status` `/stop` 等；Host 自行解释。

## Attachments（可选）

`images` / `files` 元素可含 `name`, `mime`, `data_base64`。Host 可忽略；Mock 会回显数量。

### `run_done`

Host 在一轮 Agent 运行结束时发送：

```json
{
  "type": "run_done",
  "session_key": "...",
  "reply_ctx": "...",
  "status": "completed",
  "exit_code": 0
}
```

`status` 为 `completed`、`failed`、`cancelled` 或 `timeout`；`exit_code` 仅在
Host 拿到进程退出码时提供。一个运行最多发送一次 `run_done`，常驻 Agent
开启下一轮时由 Host 生成新的 `reply_ctx`。

### Terminal 生命周期与过期 stream

生产 Host 可将 terminal 通道映射到真 PTY，但必须保持 `session_key` 与
`stream_id` 的关联：

- `terminal_open` 成功后，Host 返回 `terminal_open_ack(ok=true)`；同一 stream 重复 open 应幂等应用最新 geometry。
- `terminal_input`、`terminal_resize`、`terminal_close` 使用过期或未知 `stream_id` 时不得作用于当前 PTY，应返回 `terminal_ack(ok=false, error="stale_terminal_stream")`。
- PTY 输出使用 `terminal_out`；进程退出后先排空已缓冲输出，再发送一次 `terminal_exit`。
- `terminal_resize` 的 `cols/rows` 必须经过 Host 上限校验；客户端提供的 workdir/命令不能绕过 Host allowlist。

连接级 ownership：同一 `session_key` 已由另一条 Bridge 连接占用时，新的
`message`、`card_action` 或 `terminal_open` 不得接管，应返回 `error_code="session_in_use"`
或对应的 `terminal_open_ack(ok=false)`。对已经占用的终端，另一条连接的
`terminal_input`、`terminal_resize`、`terminal_close` 和 `terminal_permission_action`
也必须拒绝，并返回 `terminal_ack(ok=false, error="terminal_stream_in_use")`。

## 协议 v2（可选协商，向后兼容）

机器可读规范：`docs/protocol/schema/bridge.v2.schema.json`，样本：`docs/protocol/schema/samples/bridge-samples.json`。
Python（`server/test_protocol_schema.py`、`server/test_mock_host_protocol_v2.py`）和原生客户端（`apps/android/core` 契约测试）都用同一份 Schema 与样本校验。

- **协商**：App 在 `register.capabilities` 中声明 `seq` / `resume` / `session_status`。Host 只在声明后于 `register_ack` 附加 `protocol: 2`、`capabilities`（双方交集）和 `epoch`（本次 Host 进程的随机标识）。未声明的客户端（Flutter 0.1.206）收到的帧与 v1 完全相同。
- **seq**：Host 为每个 `session_key` 的 Agent 事件分配单调递增 `seq`（从 1 开始），只发给声明了 `seq` 的连接。终端帧、`pong`、`register_ack` 不带 `seq`。客户端丢弃 `seq <= 已应用 seq` 的重复帧。
- **resume**：重连并注册后，App 发送 `{"type":"resume","session_key":…,"after_seq":N,"epoch":…}`。Host 先重放 `seq > N` 的事件（带 `replayed: true`），再发 `resume_ack {last_seq, replayed}`；若超出保留窗口（默认每会话 1000 条）、`epoch` 不同（Host 已重启）或 `N` 大于 Host 的 `last_seq`，返回 `resync_required`，App 改用 Management `GET /sessions/{id}` 重新拉 transcript。
- **断线保活**：声明了 `resume` 的连接断开时，生产 Host 不立即关闭其 Agent 会话，而是保留 `detach_grace_seconds`（默认 120s）并继续把输出记入日志；新连接对该会话发送 `resume` / `session_status` / `message` / `card_action` / `cancel` 即接管。未声明 `resume` 的连接保持旧行为：断开即关闭。
- **session_status**：`{"type":"session_status","session_key":…}` → `{"type":"session_status","session_key","alive","running","last_seq","epoch"}`。
- **未知事件**：客户端必须容忍未知 `type`（显示兼容占位，不崩溃）和未知字段。
- 其余新字段（`tool_call.call_id`、`status`、`turn_id` 等）均为可选。
