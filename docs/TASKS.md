# 任务板

图例：`[x]` 完成 · `[ ]` 未做 · `[~]` 进行中

## P0 — 地基

| ID | 任务 | 状态 |
|----|------|------|
| P0-1 | 初始化仓库结构、README、LICENSE、.gitignore | [x] |
| P0-2 | ADR-001 架构决策 | [x] |
| P0-3 | 协议文档 bridge/management 子集 | [x] |
| P0-4 | Mock Host + Python 协议客户端 | [x] |
| P0-5 | Flutter Android 工程骨架 | [x] |
| P0-6 | 连接配置 + secure storage | [x] |
| P0-7 | 会话列表 + 聊天主路径 | [x] |

## P1 — 控制台核心

| ID | 任务 | 状态 |
|----|------|------|
| P1-1 | 流式回复 / thinking / tools 展示 | [x] |
| P1-2 | 权限按钮 allow/deny | [x] |
| P1-3 | mode/model/workdir 控制 | [x] |
| P1-4 | 审计日志屏 | [x] |
| P1-5 | 双方言 sessions 探测 | [x] |

## P2 — Host 目录类

| ID | 任务 | 状态 |
|----|------|------|
| P2-1 | Skills 只读 | [x] |
| P2-2 | Pairing 文本/URI | [x] |
| P2-3 | 产品文案 reframe（自有协议） | [x] |

## P3 — 控制台增强（对标成熟控制台 UX）

| ID | 任务 | 状态 |
|----|------|------|
| P3-1 | 轻量 terminal 通道 + Terminal 屏 | [x] |
| P3-2 | MCP 只读 catalog | [x] |
| P3-3 | 会话本地搜索 | [x] |
| P3-4 | Host status 仪表盘 | [x] |
| P3-5 | Workspace 只读 + git 摘要 | [x] |
| P3-6 | Prompt 历史/收藏（本机） | [x] |
| P3-7 | 终端快捷 chips / Ctrl-C | [x] |
| P3-8 | Markdown 聊天气泡 | [x] |
| P3-9 | Host memory 只读 | [x] |
| P3-10 | Host cron 只读 | [x] |
| P3-11 | Git diff 只读可视化 | [x] |
| P3-12 | 会话 Pin 置顶（本机） | [x] |
| P3-13 | Bridge 重连 UX / 手动 Reconnect | [x] |
| P3-14 | 聊天内搜索 + 命中高亮 | [x] |
| P3-15 | Transcript 导出（剪贴板） | [x] |
| P3-16 | 附件 demo 预览 | [x] |
| P3-17 | Host activity 只读事件流 | [x] |
| P3-18 | Agents 目录屏 | [x] |
| P3-19 | 会话本地备注 | [x] |
| P3-20 | 会话筛选 chips（all/pinned/running） | [x] |
| P3-21 | 斜杠命令面板 | [x] |
| P3-22 | 代码块语言标签 + 一键复制 | [x] |
| P3-23 | 会话重命名（PATCH title） | [x] |
| P3-24 | 消息长按复制 | [x] |
| P3-25 | 主题切换 system/light/dark（本机） | [x] |
| P3-26 | Host logs 只读 | [x] |
| P3-27 | Settings：字号 / 紧凑模式 / Dashboard 刷新 | [x] |
| P3-28 | 会话本地归档（列表隐藏 + Archived chip） | [x] |
| P3-29 | 审计日志筛选 / 复制 | [x] |
| P3-30 | Host Dashboard 自动刷新 | [x] |

## P4 — 远期

| ID | 任务 | 状态 |
|----|------|------|
| P4-1 | 真远程 PTY | [ ] |
| P4-2 | 相机扫码配对 | [ ] |
| P4-3 | Host 真 Hermes adapter | [ ] |
| P4-4 | 通知 / 后台重连（App 前台重连已有；系统通知仍远期） | [~] |
| P4-5 | 更完整代码高亮 / 真文件选择器附件（复制/lang 标签已有） | [~] |

## 验收命令

```bash
python3 -m py_compile server/mock-host/mock_host.py packages/huan_protocol/src/*.py
PYTHONPATH=packages/huan_protocol python3 -m unittest discover -s packages/huan_protocol/test -v
```
