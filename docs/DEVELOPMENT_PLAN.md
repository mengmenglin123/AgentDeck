# HuanHermes 完善开发规划

> 基线：0.1.194 · 2026-07-22。原则：先锁定协议契约和测试 seam，再增加真能力。

## 目标架构

```text
Flutter Console
  ├─ Connection + HostCapabilities
  ├─ Sessions + Chat + Attachments
  ├─ CatalogState (skills/mcp/memory/cron/logs/...)
  └─ NotificationIntent
          │
          ├─ Bridge WebSocket
          └─ Management REST
                  │
             Host Adapter
          ├─ Mock Adapter
          └─ Production Agent Adapter
```

## 0.1.194 — 契约与验证闭环

- [x] Workspace 与 ADR 对齐为只读
- [x] App/Mock/Python 端点行为回归
- [x] Flutter analyze/test 与 Python 测试进入 CI
- [x] Host adapter/process 语义修正
- [x] 附件大小/数量/离线持久化限制
- [x] 通知点击回到会话页
- [ ] 在独立构建刀升级 AGP 8.9.1 → 8.11.1

验收：协议测试、Flutter analyze/test、Android debug build 全绿。

## 0.1.195 — 深化 HostCapabilities Module（完成）

- [x] 将 `/status`、`projects[].capabilities` 和 adapter/process 解析集中到一个深 Module
- [x] 用 typed capability 替代 Controller/Project/Chat 内散落解析
- [ ] 所有工具入口只通过 capability Interface 决定显隐和禁用原因
- [x] 增加 Mock/兼容 Host/真 Hermes 三种 fixture 测试

收益：Host 方言知识集中，提高 locality；新增 Adapter 不再修改多个 Screen。

## 0.1.196 — Agent 作用域、终端会话与 CatalogState

- [x] 统一 Agent 作用域：共享 SessionController，目录请求带 project，模型/渠道由 Host 项目详情提供
- [x] 终端 open/ack/resize/close 生命周期与过期 stream 拒绝
- [x] 收敛目录与实时页 loading/error/refresh/timer 状态（10 个远程快照使用 CatalogState；AuditLog 实时监听；Status/HostDashboard/Sessions 使用 RefreshScheduler）
- 保留每个目录的领域渲染与字段解释，不制造万能 JSON Screen
- [x] 用一个可注入 loader Interface 覆盖自动刷新、失败恢复和 dispose 测试

收益：删除重复生命周期实现，提高测试 leverage，降低 Screen 巨石复杂度。

## 0.1.197 — 会话与通知精确深链

- [x] ToolsHub 根据当前项目 capability 门控 Skills/MCP/Memory，避免展示不可用能力

- [x] Notification payload 使用稳定 session key，而不是显示标题
- [x] Memory 目录请求带当前 project；切换 Agent 后过滤为新项目与 global 记忆
- [x] SessionController 提供按 key 跨项目定位/刷新 Interface
- [x] 点击任务完成或权限通知直接打开对应 Chat
- [ ] 前台、后台、冷启动三条 Android 集成路径回归
- [x] 手动 release job 依赖 debug/analyze/test/protocol gate

## 0.2.0 — Production Host Adapter

- [x] 新建生产 Host 进程 seam，不在 Flutter 内运行 agent loop
- [~] ProductionAgentAdapter 已管理真实子进程；具体 Claude/Codex/Hermes 驱动尚未绑定，Mock 保持参考 Adapter
- [~] 已明确进程启动、stdin/stdout、取消、工作目录和并发限制；权限、transcript、Agent 事件映射待驱动层完成
- [x] 真 PTY 在独立 PtyTerminalAdapter 上实现；不继续扩充 Mock shell 冒充 PTY
- [x] Flutter 终端区分 WebSocket 已连接与 terminal_open_ack 已确认，失败握手时禁用输入
- [x] Flutter 终端输出使用有上限本地缓冲，避免长时间 PTY 输出导致内存无限增长
- [x] Flutter 终端断线使用有限次数指数退避重连，并为每次重连生成新的 stream_id
- [x] Flutter 终端对高频 terminal_out 做批量刷新并限制待刷队列，避免 UI 重建风暴
- [x] Bridge message/card_action/cancel/terminal 帧携带 project，生产 Host 可按 Agent 项目路由

## 决策门

以下能力不得直接进入 Screen 或 Mock：

- Git 写操作：先更新 ADR/Management 协议、能力门控、确认与权限模型
- 大文件上传：先定义分片或对象存储协议；当前 base64 上限仅适合小附件
- 后台常驻连接：先确认 Android 前台服务、电量与通知策略
- 真 Hermes：必须是 Host Adapter，不得进入 Flutter agent loop

### Driver 输出契约（进行中）

- [x] 新增 Host-owned JSONL fixture Driver，覆盖半行、UTF-8、大小上限和坏 JSON
- [x] 将 text/thinking/tool/permission/done/error 映射到现有 Bridge transcript 字段
- [x] 强制 Host 注入 session key/reply context，拒绝 Agent stdout 覆盖身份
- [x] 新增 transport-neutral AgentSessionRuntime，接入 Adapter/Driver 生命周期并补 cancel/退出码/超时回归
- [x] 新增 AgentBridgeLoop，锁定 message/cancel/ping/poll 路由与坏消息 fail-closed
- [x] 新增 stdlib BridgeWebSocketTransport/Server，接入鉴权、注册、poll、连接回收、ownership 隔离回归
- [ ] 将 transport 接入部署 Host 配置、TLS 终止层、权限审计与真实 CLI Driver
- [ ] 以真实 CLI 官方稳定输出为依据，分别评估 Claude/Codex/Hermes Adapter；不复用 fixture 方言
- [x] 新增 PtyTerminalAdapter/TerminalBridgeLoop，接入 resize、过期 stream、输出排空和 WebSocket 回归
- [x] 新增 WorkspaceAllowlist，覆盖 canonical roots、missing/relative/NUL/symlink escape，并注入 Agent/PTY Adapter
- [x] 真 PTY Adapter 与部署 workdir allowlist、终端权限/审计模型联调

## 0.1.198 — Production Host 装配与终端路由加固

- [x] 用 `ProductionHostConfig` 校验显式 Agent/PTY argv、项目和安全配置
- [x] 用 `build_production_host` 装配 allowlist、PermissionGate、项目路由和 WebSocket
- [x] CI 编译清单覆盖全部 server 模块与测试模块
- [x] 默认项目无终端时拒绝未指定项目的 PTY 新建请求，避免静默跨 Agent
- [x] PTY 打开前接入 PermissionGate、终端权限卡和脱敏审计
- [x] 阻止非 owner 连接对终端 input/resize/close/permission action 的接管
- [x] 增加 Bridge 部署入口、systemd 示例和外置 TLS 配置说明
- [x] 增加项目级只读 Management catalog，切换 Agent 时隔离模型、渠道、Skills、MCP
- [x] 增加 production project-scoped/flat session CRUD 与持久项目绑定
- [ ] 增加 production Workspace、Memory、Cron、日志与活动流 Adapter
- [ ] 分别实现 Claude Code、Codex、Hermes 的官方稳定输出 Adapter

当前完成项已覆盖进程、Driver、Runtime、路由与 WebSocket transport，但仍不是完整生产
Agent 集成。下一刀优先接入部署配置/TLS/权限审计，再分别实现真实 CLI Adapter。
