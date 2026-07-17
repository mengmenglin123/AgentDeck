# LiveAgent 能力对照（HuanHermes）

目标：控制台体验尽可能接近 [LiveAgent](https://github.com/Stack-Cairn/LiveAgent)，但 **App 不做 coding agent loop**；真相源在用户服务器上的 Hermes / Codex / Claude Code（经 cc-connect 兼容 Host）。

## 对照

| LiveAgent 能力 | HuanHermes 策略 | 状态 |
|----------------|-----------------|------|
| Chat 流式 TOKEN/THINKING/TOOL | Bridge `reply_stream` / `thinking` / `tool_*` + reducer | Mock + App 完成 |
| 权限审批 | `buttons` + `card_action` | P0 完成 |
| 会话侧栏 / 新建 / 删除 | Mgmt `/sessions` | P0 完成 |
| Project / Agent 切换 | Mgmt `/projects` + 双方言 sessions | Mock + App 完成；真 Host 由用户在 App 填 token |
| mode / model / dir | Chat 工具栏 → slash message | Mock + App 完成 |
| 取消 run | Bridge `cancel` + `/stop` | Mock + App 完成 |
| 断线恢复 / seq | 自动重连 + GET transcript 重载 | Mock + App 完成 |
| 错误 / 空态 | 类型化错误 + empty UI | 完成 |
| 本地审计日志 | App 侧 redacted audit ring | 完成 |
| Skills / MCP Hub | 只读浏览（P3） | 未做 |
| 独立终端通道 | P3 | 未做 |
| Memory / Cron | Hermes 二期 / Host 能力探测 | 未做 |
| 多服务器 profile | P2 | 未做 |

## 原则

1. **Host 是真相源**（对齐 LiveAgent「桌面端是真相源」→ 服务器 CLI/Agent 是真相源）。
2. **Gateway/App 不越权**：不执行服务器本地工具；权限默认需用户确认。
3. **协议渐进**：先 Mock 可演示，再 P1 真连 cc-connect。
