# 控制台能力路线图（HuanHermes）

目标：控制台体验覆盖常见远程 Agent 控制台能力，但 **App 不做 coding agent loop**；真相源是服务器 Host 上的 Agent。

> 内容以 **HuanHermes 自有控制台能力** 为准。外部项目（含 LiveAgent 类桌面 Agent）仅作 UX/协议灵感，禁止拷贝依赖。

## 与 LiveAgent 的边界（重要）

| LiveAgent（灵感） | HuanHermes 控制台策略 |
|-------------------|----------------------|
| 本机 Electron 执行 Agent | **不做**本地 agent loop；App 只连 Host |
| 本地 Memory / Cron 引擎 | App **只读浏览** Host `/memory` `/cron` |
| 本机工作区读写 + Diff | App **只读** workspace / diff |
| Markdown / 代码高亮 | App 渲染 Host 流式回复（轻量 Markdown） |
| 会话收藏 / 搜索 | 本机 pin + 列表搜索 |
| 真 PTY / 多 Agent 桌面 | 远期；Mock 轻量 terminal 通道 |

## 状态表

| 能力 | HuanHermes 策略 | 状态 |
|------|-----------------|------|
| 连接 / 配对 URI | Mgmt + secure storage | [x] |
| 会话 CRUD + 搜索 | Management sessions | [x] |
| 聊天流式 / 权限按钮 | Bridge stream + buttons | [x] |
| Host status 仪表盘 | `/status` | [x] |
| Workspace 只读 | `/workspace` `/workspace/git` | [x] |
| Diff 只读 | `/workspace/diff` | [x] |
| Prompt 历史/收藏 | 设备本地 SharedPreferences | [x] |
| 会话 Pin | 设备本地 | [x] |
| Host Memory 只读 | `/memory` | [x] |
| Host Cron 只读 | `/cron` | [x] |
| 终端快捷 chips | Bridge `terminal_*` 演示级 | [x] |
| Markdown 聊天气泡 | 内置 MarkdownLite（无额外 pub） | [x] |
| 真 PTY / 相机扫码 | 远期 | [ ] |
| Host 真 Hermes 进程 | ADR-002 Host adapter | [ ] |
| 通知 / 后台重连策略 | 远期 | [ ] |

## 迭代原则

1. 先 `docs/protocol`，再 Mock + 客户端  
2. GitHub 只参考不拷贝、不引入运行时依赖  
3. 不碰 live 第三方 Host（9810/9820）  
4. 任务板只写 `docs/TASKS.md`

## 0.1.11+

- Bridge 自动重连 UX + 手动 Reconnect
- 聊天内搜索 / 高亮
- Transcript 导出（剪贴板 Markdown/Plain）
- 附件 demo 预览
- Host activity 只读事件流

## 0.1.12+

- Agents 目录
- 会话本地备注 + 筛选 chips
- 斜杠命令面板
- 代码块 lang + copy

## 0.1.13+

- 会话重命名 PATCH
- 消息长按复制
- 主题 system/light/dark
- Host logs 只读

## 0.1.14+

- Settings（字号/紧凑/刷新）
- 会话本地归档
- 审计筛选复制
- Dashboard 自动刷新

## 0.1.15+

- 连接公开分享 / 指纹
- 会话多选批量操作
- 聊天 tools 开关 + 跳底

## 0.1.16+

- 会话排序
- 多 profile 切换
- 聊天搜索跳转
- 高对比度

## 0.1.17+

- Host health heartbeat
- Empty-state onboarding
- Session meta export
- Terminal copy-all

## 0.1.18+

- Connection status lights
- Session recents sort
- Activity → session jump
- Audit JSON export

## 0.1.19+

- Prompt panel filter/append
- Session swipe pin/archive
- Capability badges
- Quote reply

## 0.1.20+

- Chat draft autosave
- Session project grouping
- Terminal command history
- Logs level color strips

## 0.1.21+

- Skills/MCP/Cron/Workspace local filters
- Dashboard health strip

## 0.1.22+

- Agents/Diff filters
- Status landing enrich
- Chat compact density

## 0.1.23+

- Memory/Workspace copy exports
- Catalog pull-to-refresh
- Chat timestamps + Settings version

## 0.1.24+

- More pull-to-refresh surfaces
- Dashboard status copy
- Chat jump top
- Terminal font scale
