# Production Host Adapter 接入指南

> 状态：进程生命周期 seam 与 Host-side runtime 已实现；具体 Agent 驱动尚未绑定。

## 模块分层

```text
Bridge / Management Host
        │
AgentSessionRuntime
  ├─ poll / exit / cancel / timeout 生命周期
  └─ 每轮 reply_ctx 与 run_done 语义
        │
Agent Driver
  ├─ prompt / permission / tool / transcript 映射
  └─ Claude Code / Codex / Hermes 方言
        │
AgentAdapter Protocol
        │
ProductionAgentAdapter
  └─ argv / cwd / stdio / process group / cancel / cleanup
```

`server/production_adapter.py` 不解释 Agent 输出，也不读取用户渠道或密钥配置。
它只负责安全、可测试的进程生命周期。

## 安全约束

- 命令必须来自受信任 Host 配置，并以 argv 数组传入。
- 固定使用 `shell=False`，不得拼接 shell 命令。
- `workdir` 必须是绝对路径；上层 Driver 还必须执行 workspace allowlist 校验。
- Adapter 不打印环境变量、token、prompt 或 stdout 内容。
- 每个 session 使用独立进程组；cancel 先 `SIGTERM`，超时后 `SIGKILL`。
- Host 退出时必须调用 `close_all()`。

## Driver 需要实现的映射

1. Bridge `message` → Agent stdin/CLI 参数。
2. Agent stdout → `thinking`, `reply_stream`, `tool_call`, `tool_result`, `buttons`, `run_done`。
3. Bridge `cancel` → `ProductionAgentAdapter.cancel()`。
4. Agent 权限请求 → 稳定 permission id 和可审计 card action。
5. transcript、mode、model、workdir → Management 会话详情。
6. CLI 不存在、退出码、超时、输出截断 → 协议错误事件。

## Host-side runtime

`server/agent_session_runtime.py` 将 Adapter 与 Driver 组合成一个不依赖传输层的
生命周期 Interface。Bridge handler 可调用 `start`、`send`、`poll`、`begin_run`
和 `cancel`，再转发返回的协议字典。它保证：

- 进程退出后先排空已写入 stdout，再补充唯一的 `run_done`。
- 非零退出码映射为 `failed`；主动取消映射为 `cancelled`；超时映射为 `timeout`。
- 常驻进程可通过 `begin_run` 开启下一轮，并更新本轮 `reply_ctx` 与 timeout。
- Agent 已发送 `run_done` 时不会重复生成；session 结束时统一回收管道。

## 当前验收

```bash
PYTHONWARNINGS=error::ResourceWarning \
PYTHONPATH=server \
python3 -m unittest discover -s server -p 'test_*.py' -v
```

测试使用 Python 子进程作为可控 fixture，不要求安装 Claude Code、Codex 或 Hermes，
因此不能把这些测试解释为“真实 Agent 已接通”。

## Host-owned JSONL fixture driver

`server/jsonl_agent_driver.py` 提供 `JsonlAgentDriver`，把受控 Agent
stdout 的 JSON Lines fixture 转成 Bridge 事件。它是第二个可测试的 Driver
seam，不是 Claude Code、Codex 或 Hermes 私有输出格式的兼容承诺。

输入事件示例：

```jsonl
{"type":"text_delta","text":"hello","done":false}
{"type":"tool_call","name":"shell","input":"pwd"}
{"type":"tool_result","name":"shell","output":"/srv/app"}
{"type":"permission","content":"Allow command?","buttons":[[{"text":"allow","data":"perm:allow"}]]}
{"type":"done","status":"completed"}
```

Driver 的接口约束：

- `feed(bytes)` 支持任意 stdout 分片，并只返回完整行对应的事件。
- `finish()` 处理最后一条无换行记录；重复调用安全返回空列表。
- 每行有大小上限，坏 JSON、非对象和未知事件转为可消费的结构化错误回复。
- UTF-8 解码采用替换策略，不因单个坏字节崩溃。
- `session_key` 与 `reply_ctx` 由 Host 构造并注入；Agent 输出中的同名字段会被忽略。
- 不打印 prompt、token 或 Agent 原始 stdout；限制和事件内容仍应由上层审计策略控制。

运行回归：

```bash
PYTHONPATH=server python3 -m unittest server.test_jsonl_agent_driver -v
```

## Bridge routing seam

`server/bridge_agent_loop.py` 将规范化的 Bridge `message`、`cancel`、`ping`
和轮询调用映射到 `AgentSessionRuntime`。它不拥有 WebSocket、认证或 socket
写入；实际 Host handler 只需负责鉴权/帧解析/发送，并周期性调用 `poll`。

路由层的安全约束：

- `workdir` 必须由受信任的 Host resolver 提供，不直接相信客户端路径。
- 非法消息、未知消息和未知 session 转为结构化错误，不让单条坏帧杀死连接。
- `session_key`、`reply_ctx` 仍由 Host/Bridge 输入上下文控制；Agent stdout 不能覆盖。
- 多轮常驻 Agent 必须先完成上一轮，再用 `begin_run` 生成新的 `reply_ctx`。

当前仍未绑定真实 WebSocket handler，也未声称真实 Claude/Codex/Hermes CLI 已接入。

## WebSocket transport

`server/bridge_websocket.py` 提供 stdlib-only 的 `BridgeWebSocketTransport` 与
`BridgeWebSocketServer`：

- 只接受 `GET /bridge/ws`、WebSocket version 13 和合法 `Sec-WebSocket-Key`。
- 支持 `Authorization: Bearer ...`、`X-Bridge-Token` 或 query `token`；比较使用常量时间比较。
- 要求客户端 frame masked，限制 header/frame 大小，处理 text、close、ping/pong。
- 注册前只允许 `register`/`ping`；Agent 输出只回传给创建该 session 的连接。
- 连接断开只回收本连接创建的 session，不调用全局 `close_all()`。
- `BridgeWebSocketServer` 默认绑定 `127.0.0.1`；它不实现 TLS，生产部署必须使用 TLS 终止层或受保护内网。

它已经是可运行的 Host transport，但尚未接入具体生产配置、权限审计存储和真实
Claude/Codex/Hermes Driver。

## 真 PTY terminal adapter

`server/pty_terminal_adapter.py` 与 `server/terminal_bridge_loop.py` 提供生产 Host
终端 seam：

- `PtySpec` 只接受显式 argv；PTY 子进程独立 session/process group，不拼接 shell 命令。
- master fd 非阻塞读取，PTY 退出后仍可排空缓冲输出；`SIGTERM` 超时后升级 `SIGKILL`。
- `resize` 使用 `TIOCSWINSZ` 并发送 `SIGWINCH`；geometry 有 Host 侧上限。
- `TerminalBridgeLoop` 校验 `session_key/stream_id`，拒绝过期 stream，并生成 `terminal_out`/`terminal_exit`。
- transport 只回传当前 WebSocket 创建的 terminal session，不向其它连接广播 PTY 数据。

这仍是 Host adapter，不把 shell/PTY 放入 Flutter；实际部署必须再接入 workdir
allowlist、权限确认、审计存储和 TLS 保护。

## Permission audit deployment

使用 `server/host_security_config.py` 从 Host 配置构造 `PermissionGate`，并为
`[audit].permission_log_path` 提供本机绝对路径。`JsonlPermissionAuditStore` 写入
脱敏 JSONL，不记录 prompt、reply context 或 Agent 原始按钮 ID；文件必须由 Host
用户独占访问。审计文件达到配置上限时权限请求 fail-closed，部署侧应使用受保护
的轮转策略，而不是让应用自动覆盖旧审计记录。

## Workspace allowlist

`server/workspace_allowlist.py` 集中处理 Host 的 workdir policy：

```python
policy = WorkspaceAllowlist(["/workspace"])
agent = ProductionAgentAdapter(spec, workdir_validator=policy.resolve)
terminal = PtyTerminalAdapter(pty_spec, workdir_validator=policy.resolve)
```

Bridge/Terminal loop 应使用 `policy.message_resolver()` 或项目配置 resolver，
然后仍把 `policy.resolve` 注入 Adapter 作为第二道防线。当前实现只接受已有目录，
并以 canonical path 检查 symlink 逃逸；真实部署仍需把项目配置、用户身份和 Linux
权限绑定起来。

## Typed production assembly

`server/production_host_config.py` 将 server、auth、workspace、projects、permissions
和 audit 配置解析为不可变配置；每个项目必须提供显式 `command` argv，可选
`terminal_command` argv。`server/production_host_factory.py` 随后为每个项目创建独立
的 Agent/PTY adapter 与 loop，并用 `ProjectAgentRouter`、`ProjectTerminalRouter`
和共享的 `PermissionGate` 连接到 WebSocket transport。

```python
config = ProductionHostConfig.load("/etc/huanhermes/host.toml")
host = build_production_host(config)
host.server.serve_forever()
```

生产部署检查清单：

1. 预先创建 audit 文件父目录，并限制 Host 用户的读写权限。
2. 使用 Host-owned driver 替换示例中的占位路径；不要假设 fixture JSONL 就是第三方 CLI 方言。
3. 仅通过 TLS 终止层或受保护内网暴露 WebSocket；当前 stdlib server 不提供 TLS。
4. 默认项目不支持终端时，客户端创建新 PTY 必须显式发送 `project`；已绑定的终端会话只能继续使用原项目。
5. 生产默认要求 `terminal_open_required = true`；PTY 启动前先发送权限卡，决定绑定
   `session_key + stream_id` 并写入 PermissionGate 审计。

运行入口为 `server/production_host.py --config <path>`，会同时启动 Bridge 与只读
Management catalog。Management 使用独立 `mgmt_token`，并从每个 `[projects.*]`
表读取 `models`、`channels`、`skills` 和 `mcp_servers`；App 传入 `project` 后只返回
该项目的数据。仓库同时提供
`server/examples/huanhermes-host.service` 和 `server/examples/nginx-bridge.conf`，
用于展示进程托管与 TLS 终止的最小形状。它们是需要部署者审查和改写的模板，不会
自动安装。当前 Management 已覆盖项目、目录和 project-scoped/flat session CRUD；session
元数据持久化到配置的 `session_store_path`。尚不包含 Workspace、Memory、Cron、日志
或活动流。
