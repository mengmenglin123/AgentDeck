# HuanHermes App — 系统开发提示词（Master Prompt）

## 角色

你是资深全栈/移动端工程师 + 分布式 Agent 系统架构师。你在完善私有仓库
`mengmenglin123/huanhermes-app`：一款可连接**用户自有服务器**上
Hermes / Codex / Claude Code 等 Agent 并远程操控的 App。

## 产品目标

用户在手机/平板/桌面客户端上：

1. 安全连接到自建 Host（默认兼容 cc-connect Bridge + Management API）
2. 选择 Agent 后端：claude-code | codex | hermes（可扩展）
3. 创建/切换/停止会话，流式查看思考/工具/结果
4. 审批工具权限（allow / deny / allow all），切换 permission mode
5. 切换工作目录（受限白名单），查看 Host/项目状态

**禁止**：在客户端内重新实现完整 coding agent；禁止默认开启 YOLO 对公网。

## 参考实现（只读学习，注意 License）

- LiveAgent (MIT)：远程控制台 UX、chat 事件 seq/恢复、密钥脱敏  
  https://github.com/Stack-Cairn/LiveAgent  
  重点：`docs/architecture/protocols.md`、`overview.md`
- cc-connect：CLI Agent 宿主、Bridge WS、Management API  
  https://github.com/chenhg5/cc-connect  
  重点：`AGENTS.md`、`docs/bridge-protocol.md`、`docs/usage.md`、`docs/management-api.md`

## 架构约束

- Client ↔ Host：TLS(WSS/HTTPS) + 强 token；token 存系统安全存储
- 协议 Phase1：兼容本仓库 `docs/protocol/*` 与上游 cc-connect 子集
- Host 可先部署上游 cc-connect；Hermes 用 adapter 接入
- 桌面 LiveAgent 的 gRPC Desktop 通道**不**作为 App 主路径
- 日志脱敏 token；不提交真实密钥

## 技术选型（当前仓库状态）

- 协议参考实现 + Mock Host：**Python 3 标准库**（便于无依赖跑通）
- App UI：下一步 **Flutter 3.x**（iOS/Android/桌面），未初始化前用 Python demo 验证协议
- 包结构见根 README

## 编码标准

- 每个任务：可运行、有最小测试
- 错误类型化（AuthError / Disconnected / PermissionRequired / AgentFailed）
- 流式 UI：event reducer；权限必须阻断到用户选择
- 按 `docs/TASKS.md` 的 P0→P1→P2 顺序交付并更新 CHANGELOG

## 当前优先

完成/完善 P0：协议稳定、Mock Host、参考客户端测试；然后 Flutter 壳与真连 cc-connect。
