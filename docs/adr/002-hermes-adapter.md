# ADR-002: Hermes Agent Adapter（二期）

- **状态**: Accepted（设计冻结；实现可渐进）  
- **日期**: 2026-07-17  
- **关联**: [ADR-001](001-architecture.md)、`docs/protocol/*`  
- **约束**: 外部项目仅作设计灵感；**不**修改用户已部署 Host 的渠道/密钥；**不**把第三方宿主写进产品安装路径。

## 背景

| Agent | 驱动方式 | 阶段 |
|-------|----------|------|
| Claude Code | Host 侧 CLI/进程 | Phase 1+ |
| Codex | Host 侧 CLI/进程 | Phase 1+ |
| Hermes | Host 侧 adapter | Phase 2 |

Hermes 有独立会话/工具模型，不能假设与其它 agent 内部实现一一同构。App 只认识 Bridge/Mgmt。

## 决策

1. **Hermes 进程只在服务器 Host 侧**  
   App 继续当控制台；`agent_type=hermes` 的 project 由 Host 适配。

2. **能力声明**  
   `GET /projects` 返回 `capabilities[]`，App 工具栏按能力显隐。

3. **实现路径（Host 侧，非本 App 仓强制）**  
   - **A.** 自研 Host 增加 `agent_type=hermes` 驱动  
   - **B.** 本仓 Mock 用 `hermes` project 演示协议形状（**不是**真 Hermes 进程）

4. **不做**  
   - 在 Flutter 内嵌 Hermes agent loop  
   - 为联调改用户线上服务配置  
   - 把外部宿主源码拷进本仓  

## Mock 行为

- project `name=hermes`  
- 回复带 `[hermes-mock]` 与 `memory.search` 工具事件  
- 证明 App 路径可通；真 adapter 属于 Host 部署工作

## 后果

- P2 App：选 hermes 项目可聊、可 cancel、可 capability 门控  
- 真 Hermes：用户在自己的 Host 上接 ADR 接口
