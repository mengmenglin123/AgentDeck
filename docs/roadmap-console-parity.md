# 控制台能力路线图（HuanHermes）

目标：控制台体验覆盖常见远程 Agent 控制台能力，但 **App 不做 coding agent loop**；真相源是服务器 Host 上的 Agent。

> 内容以 **HuanHermes 自有控制台能力** 为准。外部项目仅作 UX/协议灵感，禁止拷贝依赖。

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
| MCP 只读 | GET /mcp | 完成 |
| 配对 URI | GET /pairing + Connect 导入 | 完成 |
| 会话搜索 | 本地过滤 title/project/key | 完成 |
| Hermes 形态会话 | Mock + ADR-002 | Mock 完成 |
| 轻量终端通道 | Bridge terminal_* + Terminal 页 | 完成（Mock 回显，非真 PTY） |
| 终端快捷操作 | help/pwd/ls/y/n/^C chips | 完成 |
| Prompt 历史/收藏 | 设备本地 SharedPreferences | 完成 |
| Host 状态面板 | 可刷新 /status + shortcuts | 完成 |
| 工作区只读浏览 | GET /workspace + /workspace/git | 完成（Mock 树） |
| 真远程 PTY / 相机扫码 | 可选后续 | 未做 |
| Diff 可视化 / push | 可选后续 | 未做 |

## 外部灵感（只参考）

常见远程 Agent 控制台共性（CC Pocket / remote terminal / ACP UI 等社区项目）：

1. QR/配对 URI 导入  
2. 会话列表 + 并行会话  
3. 权限审批按钮  
4. 终端快捷键（y/n、Ctrl-C）  
5. 本地 prompt 收藏/历史  
6. 工作区/文件只读浏览 + git 状态  
7. Host 健康面板（uptime、会话数）  

本仓全部在 `docs/protocol` + Mock + Flutter 自实现，**不安装、不依赖** 上述项目。

## 原则

1. Host 是真相源。  
2. 协议写在本仓 `docs/protocol`。  
3. 开发主路径：**Mock ↔ App**，再连自研 Host。
