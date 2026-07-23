# 新对话接续

## 当前锚点

| 项 | 值 |
|----|-----|
| 功能版本 | **0.1.198+198（工作区，尚未提交）** |
| 已 ship | **0.1.193+193 / 7e516b5** |
| HEAD 文档 | `565a3d6` |
| 当前主题 | CatalogState、Agent 作用域、终端协议与通知精确深链 |
| Python 协议测试 | **17 个** |
| Server 测试 | **86 个** |
| Flutter 测试 | **50 个** |

## 已完成但尚未提交

- Workspace 恢复为协议规定的只读能力；移除不可用 Git commit/push/pull
- CI 增加 Flutter analyze/test、Python compile/test 和 PR 触发
- Host adapter/process 判断修正，版本语义统一
- typed HostCapabilities Module 已接入 Connection/Project/Chat
- Skills/MCP/Agents/Memory/Cron/Logs/Activity/Pairing 已迁移到 CatalogState，具备统一自动刷新与过期响应隔离
- AuditLog 改为直接 ChangeNotifier 监听
- Workspace/Diff 已使用路径安全的原子快照状态
- Status/HostDashboard/Sessions 已迁移 RefreshScheduler，所有 Screen 不再直接维护周期 Timer
- 任务完成/权限通知使用稳定 session_key，可跨项目定位并打开 Chat
- 真文件/相册/相机附件统一限制：5 MB/项、10 MB/总计、最多 4 项
- 带附件消息失败时不进入离线持久化，并保留编辑内容
- 通知点击/冷启动 payload 可回到会话 Tab
- 当前用户原有未提交改动：Status/Catalog AppBar 收敛，必须保留

## 后续顺序

1. 本地或 CI 跑 `flutter analyze && flutter test`
2. 修完所有静态/测试问题后再构建 APK
3. 将剩余工具入口迁移到 capability Interface
4. 抽 Catalog Screen 的加载/刷新/筛选状态 Module
5. 设计生产 Host adapter；真 PTY 与真 Hermes 依赖该 seam

## 硬限制

- 只改本仓
- 禁 live **9810/9820**；禁 `/root/.cc-connect`
- Workspace 默认只读；若要写 Git，必须先更新 ADR、协议、能力门控与权限模型
- token 不进日志、通知、剪贴板公开摘要
- 不覆盖未提交的 `status_screen.dart` / `catalog_ui.dart`

## 验收

```bash
python3 -m py_compile server/mock-host/mock_host.py packages/huan_protocol/src/*.py
PYTHONPATH=packages/huan_protocol python3 -m unittest discover -s packages/huan_protocol/test -v
cd apps/mobile && flutter analyze && flutter test
```

## 本轮新增（0.1.198 工作区）

- `server/jsonl_agent_driver.py`：Host-owned JSONL fixture Driver，输出映射保持与 Flutter/Python transcript reducer 一致。
- `server/test_jsonl_agent_driver.py`：7 项回归覆盖分片、身份注入、事件映射、坏输入、大小限制和结束刷新。
- CI 已纳入 Driver `py_compile` 与单测；当前不代表真实 Claude/Codex/Hermes CLI 已接通。
- Android SDK 不在本机；通知 payload 单测已通过，前台/后台/冷启动真机验证留给 GitHub Actions/设备。

## 下一刀

1. 基于各 CLI 的官方稳定输出分别设计 Claude/Codex/Hermes Adapter，禁止把 fixture 方言当真实兼容层。
2. 为 production Management 补 Workspace、Memory、Cron、日志和活动流 Adapter。
4. 在 Android CI 或真机环境验证通知初始化、权限、前台点击、后台点击和冷启动深链。

## 本轮新增（Production Host assembly）

- `server/production_host_config.py` / `server/production_host_factory.py`：typed TOML、项目级 Agent/PTY、allowlist、PermissionGate、路由和 WebSocket 装配。
- `server/production_host.py`：生产 Bridge + Management CLI 入口；配置或监听失败不输出 token/prompt。
- `server/production_management.py`：独立 token 的只读目录服务，按 project 隔离模型、渠道、Skills、MCP 和 Agents。
- `server/examples/huanhermes-host.service` / `server/examples/nginx-bridge.conf`：进程托管与外置 TLS 模板。
- 默认 Agent 无终端时，新 PTY 必须显式携带 project，不再静默回退到其它 Agent。
- 生产 PTY 打开前经过 PermissionGate；非 owner 连接不能 input/resize/close 或代点权限。
- `terminal_permission` / `terminal_permission_action` 已加入 Bridge 契约，权限决定绑定 `session_key + stream_id`。
- 生产 PTY 打开前经过 PermissionGate；非 owner 连接不能 input/resize/close 或代点权限。
- 当前仍未绑定真实 Claude Code/Codex/Hermes CLI；Management 尚未覆盖 Workspace、Memory、Cron、日志与活动流。

## 本轮新增（Agent lifecycle runtime）

- `server/production_adapter.py`：已退出进程仍可排空 stdout，并提供 `exit_code()`。
- `server/agent_session_runtime.py`：协调 poll、退出码、cancel、timeout、唯一 `run_done` 和常驻进程多轮 `reply_ctx`。
- `server/test_agent_session_runtime.py`：10 项子进程生命周期回归；Server 测试总数 35 项。
- 当前仍未完成：部署配置/TLS/权限审计，以及绑定真实 Claude/Codex/Hermes CLI 方言。

## 本轮新增（Bridge routing seam）

- `server/bridge_agent_loop.py`：将 `message/cancel/ping/poll` 路由到 Runtime，坏消息 fail-closed。
- `server/test_bridge_agent_loop.py`：5 项契约回归覆盖首轮、多轮 `reply_ctx`、取消、ping、未知 session。
- Bridge 路由已接入独立 WebSocket transport；权限审计和真实 CLI 仍未接入。

## 本轮新增（WebSocket transport）

- `server/bridge_websocket.py`：真实 stdlib WebSocket handshake、token 鉴权、masked frame、ping/pong、register 门控、poll 和 threaded listener。
- `server/test_bridge_websocket.py`：7 项 socketpair/TCP 回归，覆盖鉴权、注册、事件回传、连接隔离、shutdown。
- Server 测试目前共 54 项；transport 尚未接入生产配置、TLS 终止层、权限审计存储和真实 CLI。

## 本轮新增（真 PTY terminal）

- `server/pty_terminal_adapter.py`：显式 argv、独立 PTY process group、非阻塞 master、输入输出、resize、退出码、取消和回收。
- `server/terminal_bridge_loop.py`：`terminal_open/input/resize/close` 映射、stream_id 校验、输出排空和唯一 `terminal_exit`。
- `server/test_pty_terminal_adapter.py`、`server/test_terminal_bridge_loop.py`：11 项真实 Unix PTY 回归。
- WebSocket 增加 terminal frame 端到端回归；Server 测试目前共 54 项。
- 未完成边界：workdir allowlist、权限确认/审计、TLS 部署和真实 Agent CLI。

- WebSocket transport 新增 connection ownership 防接管回归：其它连接不能发送 Agent 输入或替换 terminal stream。

## 本轮新增（workspace allowlist）

- `server/workspace_allowlist.py`：canonical existing roots、子目录 containment、symlink escape/relative/NUL/缺失路径拒绝。
- `server/test_workspace_allowlist.py`：6 项回归，并验证 Production Agent/PTY Adapter 的 validator 注入。
- Server 测试目前共 54 项；下一步是将 allowlist 与部署项目配置、权限审计和 TLS 终止层真正绑定。

## 本轮新增（PermissionGate）

- `server/permission_gate.py`：Host 生成权限 ID/按钮，绑定 session/reply context，支持 TTL、一次性决策和 scope 级短期 `allow_all`。
- `server/agent_session_runtime.py`：将 JSONL permission 事件转换为 Host card，并把合法 `card_action` 转成受控 `permission_response`。
- WebSocket ownership 同时保护 `message` 与 `card_action`，防止其它连接代点权限卡片。
- 运行时与 WebSocket 回归覆盖脱敏、错上下文、一次性决策和跨连接隔离；Server 测试基线为 70 项。

## 本轮新增（Agent 作用域与终端状态）

- Memory 目录支持 `?project=`，保留 global 记忆并过滤其它 Agent 的 project-scoped 记忆；ToolsHub、Chat、Sessions、Host Dashboard 均传入当前 project。
- ToolsHub 终端入口遵循当前项目 `terminal` capability，不再对不支持终端的 Agent 显示可用入口。
- TerminalScreen 只有收到 `terminal_open_ack(ok=true)` 后才允许输入、快捷命令和 resize；断线、失败握手、Host 退出都会清空 ready 状态。
- TerminalScreen 使用有上限的 `TerminalBuffer` 保留本地显示窗口，长时间 PTY 输出不会无限增长内存；新增独立缓冲单测。
- TerminalScreen 断线后最多有限次指数退避自动重连，每次新建 `stream_id`；重连策略单测覆盖退避上限与停止条件。
- TerminalScreen 用 `TerminalOutputBatcher` 合并高频 `terminal_out`，并限制待刷字符数；新增批处理与丢弃回归测试。
- Bridge 的 message、card_action、cancel、terminal 帧现在携带 project，后续 Production Host 可按 Claude/Codex/Hermes 项目选择对应 Runtime。
