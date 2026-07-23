# Server（HuanHermes Host）

## Mock Host（推荐开发路径）

```bash
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 \
HUAN_BRIDGE_TOKEN=dev-bridge-token-change-me \
HUAN_MGMT_TOKEN=dev-mgmt-token-change-me \
python3 mock-host/mock_host.py
```

- Bridge: `ws://127.0.0.1:$HUAN_BRIDGE_PORT/bridge/ws?token=...`  
- Mgmt: `http://127.0.0.1:$HUAN_MGMT_PORT/api/v1`  

协议：`../docs/protocol/*`。

## 自研 Host

实现 `docs/guides/self-host-compat.md` 中的子集即可被 App 使用。  
`examples/` 仅是 **本仓** 配置字段示例，不是「去装某个外部项目」的说明。

## 注意

- 不要占用用户机器上已有服务的端口而不沟通  
- 不要把用户生产密钥写进示例文件提交 git  


## Production Agent Adapter seam

`production_adapter.py` 提供与具体 CLI 无关的 `AgentAdapter` Protocol 和
`ProductionAgentAdapter` 进程生命周期实现：

- 仅接受显式 argv，固定 `shell=False`
- 每个 session 独立进程组
- stdin/stdout、非阻塞读取、取消与强制回收
- 最大并发会话限制
- 不记录命令环境、token 或消息正文

当前状态：**进程 seam 与 Host-owned JSONL fixture Driver 已实现，但尚未绑定 Claude Code/Codex/Hermes 的真实消息格式**。
接入步骤见 `../docs/guides/production-host-adapter.md`。

`agent_session_runtime.py` 与 `bridge_agent_loop.py` 已提供可测试的 Host-side
生命周期/路由 seam；WebSocket transport 已实现，部署 Host 仍需通过
`docs/protocol/*` 实现鉴权、权限和审计策略。

## WebSocket transport

`bridge_websocket.py` 提供可测试的 stdlib WebSocket listener，默认建议绑定
`127.0.0.1`，支持 token 鉴权、register 门控、ping/pong、Agent poll 和连接级
session 回收。它不提供 TLS；暴露到不可信网络前必须放在 TLS 终止层之后。

## Production PTY

`pty_terminal_adapter.py` 与 `terminal_bridge_loop.py` 是生产 Host 的真 PTY seam，
支持显式 argv、输入输出、resize、过期 stream 拒绝、退出和取消。Mock Host 的
`HUAN_REAL_PTY=1` 仍仅用于离线演示；部署前必须补 workdir allowlist、权限审计
和 TLS/网络策略。

## Workspace allowlist

部署 Host 时应以 `WorkspaceAllowlist` 配置 canonical roots，并同时注入
`ProductionAgentAdapter`、`PtyTerminalAdapter` 和 Bridge/Terminal resolver；不要
直接把客户端 `workdir` 传给进程启动器。

## Permission audit

生产 Host 应从 `examples/config.example.toml` 的 `[permissions]` 与 `[audit]`
配置构造 `HostSecurityConfig`。`JsonlPermissionAuditStore` 只写入脱敏的权限
动作记录，使用 `0600` 文件权限、拒绝 symlink 目标、限制文件大小，并默认
`fsync`；审计写入失败时 `PermissionGate` 不改变待处理或已消费状态。

## Production Host assembly

`production_host_config.py` 负责加载并校验 TOML，`production_host_factory.py`
把 workspace allowlist、共享 PermissionGate、每个项目的 Agent/PTY loop、项目路由
和 WebSocket transport 组装起来。最小流程如下：

```python
from production_host_config import ProductionHostConfig
from production_host_factory import build_production_host

components = build_production_host(ProductionHostConfig.load("/etc/huanhermes/host.toml"))
try:
    components.management.start()
    components.server.serve_forever()
finally:
    components.close()
```

`examples/config.example.toml` 中的 `command` 是 Host-owned driver 的显式 argv，
不是 Claude Code、Codex 或 Hermes 的真实兼容声明。部署者必须提供对应 adapter，
并预先创建 `[audit].permission_log_path` 的父目录，让运行用户独占访问；不要把
客户端输入拼进命令。WebSocket 当前不提供 TLS，公网部署必须放在 TLS 终止层后。

如果 `server.default_project` 没有 `terminal_command`，终端新建请求必须显式携带
`project`；不会自动回退到其它项目，避免把 PTY 连接发错 Agent。

生产配置默认要求打开 PTY 前通过 `PermissionGate` 确认（`[permissions]`
中的 `terminal_open_required = true`）。Host 先发送 `terminal_permission`，只有
收到绑定当前 `session_key`/`stream_id` 的 `terminal_permission_action` 后才启动
子进程；决定会写入同一份脱敏权限审计 JSONL。

启动 Bridge Host：

```bash
python3 production_host.py --config /etc/huanhermes/host.toml
```

`examples/huanhermes-host.service` 与 `examples/nginx-bridge.conf` 分别提供 systemd
和外置 TLS 终止模板。模板路径、用户、域名和证书必须按部署环境修改。

CLI 同时启动 Bridge WebSocket 与只读 Management catalog。Management 使用独立
`mgmt_token`，提供 `/status`、`/projects`、项目详情、`/skills?project=`、
`/mcp?project=`、`/agents?project=` 和 `/pairing`。其中模型、渠道、Skills 与 MCP
完全来自对应项目的 Host 配置，因此切换 Agent 后不会复用上一个项目的目录。
Production Management 已提供 project-scoped 与 flat 双路径的 session CRUD，记录持久化
到 `[management].session_store_path`，并把同一 session key 的项目归属交给 Bridge
Router 校验。当前尚不提供 Workspace、Memory、Cron、日志等端点；这些能力不能由
App 或模板假装存在。
