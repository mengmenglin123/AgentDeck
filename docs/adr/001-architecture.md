# ADR-001: HuanHermes 总体架构

- **状态**: Accepted  
- **日期**: 2026-07-17  
- **决策者**: mengmenglin123 + 安全工程助手  

## 背景

需要一款 App，连接用户**自有服务器**上的 Hermes / Codex / Claude Code 等 Agent 并远程操控。  
已分析：

- [LiveAgent](https://github.com/Stack-Cairn/LiveAgent)：本地优先桌面 Agent + Gateway 远程 WebUI  
- [cc-connect](https://github.com/chenhg5/cc-connect)：CLI Agent 宿主 + IM/Bridge 入口  

## 决策

1. **App 不做 coding agent loop**  
   客户端只做控制台：连接、会话、流式 transcript、权限审批、状态。

2. **服务器 Host 采用「CLI 驱动」模型（对齐 cc-connect）**  
   Phase 1：直接部署 / 兼容 **cc-connect Bridge WebSocket + Management REST**。  
   Phase 2：可自研 Host，保留 Bridge 兼容层，并增加 Hermes adapter。

3. **UI / 事件语义对齐 LiveAgent 思想**  
   - 会话侧栏 + running 态  
   - 流式事件 + 可恢复游标（seq 语义，实现可渐进）  
   - 密钥脱敏；网关不越权执行本地工具  
   - **不**以 LiveAgent 桌面 gRPC 作为 App 主路径  

4. **Hermes 二期**  
   不阻塞 Claude Code / Codex MVP；单独 ADR 定 adapter。

## 后果

| 正面 | 负面 |
|------|------|
| 快速验证产品；复用成熟 CLI | 依赖上游 Bridge 草案演进 |
| 安全边界清晰 | 完整终端 / MCP 市场需后置 |
| 可替换 Host 实现 | Hermes 需额外开发 |

## 非目标（MVP）

- 重写 Claude/Codex 内核  
- 默认公网无审批高权限  
- 飞书/Telegram 全家桶内置到 App（用户可自建 cc-connect）  
