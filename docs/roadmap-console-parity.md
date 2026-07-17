# 控制台能力路线图（HuanHermes）

目标：控制台体验覆盖常见远程 Agent 控制台能力，但 **App 不做 coding agent loop**；真相源是服务器 Host 上的 Agent。

> 内容以 **HuanHermes 自有控制台能力** 为准。

| 能力 | HuanHermes 策略 | 状态 |
|------|-----------------|------|
| 多会话列表 | Mgmt sessions 双方言 | 完成 |
| 流式回复 | Bridge reply_stream | 完成 |
| thinking / tools | Bridge 事件 + reducer | 完成 |
| 权限按钮 | buttons/card_action | 完成 |
| mode / model / dir | 工具栏 + slash | 完成 |
| Stop / cancel | Bridge cancel | 完成 |
| 断线重连 / 历史 | reconnect + session detail | 完成 |
| 审计 | 本地脱敏 ring | 完成 |
| Project / Agent 切换 | `/projects` + capabilities | 完成 |
| 多服务器 profile | 安全存储多 profile | 完成 |
| 附件 | images/files 协议 + demo UI | 完成 |
| Skills 只读 | GET /skills | 完成 |
| 配对文本 | GET /pairing | 完成 |
| Hermes 形态会话 | Mock + ADR-002 | Mock 完成 |
| 终端独立通道 | 远期 | 未做 |

## 原则

1. Host 是真相源。  
2. 协议写在本仓 `docs/protocol`。  
3. 开发主路径：**Mock ↔ App**，再连自研 Host。
