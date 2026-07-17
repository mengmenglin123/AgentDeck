# ADR-001: HuanHermes 架构

- **状态**: Accepted  
- **日期**: 2026-07  

## 背景

需要一个 **Android 控制台**，远程管理服务器上的 coding agent（Claude Code / Codex / Hermes），而不是在手机上跑完整 agent loop。

## 决策

1. **App = 控制台 only**  
   会话列表、流式 transcript、权限、mode/model/dir/stop、审计。不在客户端重写 agent loop。

2. **Host = 服务器真相源**  
   Host 暴露 **HuanHermes Bridge WebSocket** + **Management REST**（规范在 `docs/protocol/`）。  
   Phase 1 参考实现：**本仓 Mock Host**。生产可用 **自研兼容 Host** 驱动 CLI/Agent 进程。

3. **协议本仓拥有**  
   字段与路径以 `docs/protocol/*` 为准。可借鉴业界常见 Bridge/Mgmt 形状，但文档与代码默认语言是 HuanHermes，不要求用户安装特定第三方宿主。

4. **UI 事件语义**  
   流式、thinking、tool、permission buttons、run cancel — 对齐常见远程控制台体验；实现完全在本仓 Flutter。

5. **不做**  
   - 把第三方桌面 gRPC 当 App 主路径  
   - 把 IM 全家桶内置进 App  
   - 拷贝外部项目源码进本仓  

## 后果

- 开发主路径：Mock Host ↔ App  
- 扩展：自研 Host 按 `docs/guides/self-host-compat.md` 实现子集  
- Hermes：见 ADR-002（Host 侧 adapter，App 只消费协议）
