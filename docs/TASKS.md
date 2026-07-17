# 任务板

图例：`[x]` 完成 · `[ ]` 未做 · `[~]` 进行中

## P0 — 地基

| ID | 任务 | 状态 |
|----|------|------|
| P0-1 | 初始化仓库结构、README、LICENSE、.gitignore | [x] |
| P0-2 | ADR-001 架构决策 | [x] |
| P0-3 | 协议文档 bridge/management 子集（本仓拥有） | [x] |
| P0-4 | Bridge 客户端（Python 参考）+ 心跳/鉴权字段 | [x] |
| P0-5 | Mgmt 客户端子集（Python） | [x] |
| P0-6 | Mock Host（Bridge + Mgmt） | [x] |
| P0-7 | App 连接配置页 + 安全存储 | [x] Flutter Android 工程 + Connect 页 |
| P0-8 | 会话列表 + 新建 + 聊天页 | [x] Flutter Sessions + Chat |
| P0-9 | 流式 transcript reducer | [x] Python + Flutter reducer + Chat UI |
| P0-10 | 权限 allow/deny/allow_all | [x] Mock + Flutter 权限按钮 UI |

## P1 — 控制台完备 + Host 对接

| ID | 任务 | 状态 |
|----|------|------|
| P1-1 | server 示例 config + 文档 | [x] 本仓 example（非外部产品配置） |
| P1-2 | 连接真实 Host（自研/Mock 生产形态） | [x] 客户端双方言 + 连接指南 |
| P1-3 | Codex / 多 project 切换 | [x] Sessions project filter + mock projects |
| P1-4 | mode/model/dir/stop UI 映射 | [x] Chat toolbar + slash + cancel |
| P1-5 | 断线续传 / 重载会话 | [x] Auto-reconnect + GET session transcript |
| P1-6 | 取消 run | [x] Bridge cancel + stop button |
| P1-7 | 本地审计日志 | [x] Redacted in-app audit ring |
| P1-8 | 错误与空态 | [x] Empty sessions/chat + typed errors |

## P2 — Hermes 与产品化

| ID | 任务 | 状态 |
|----|------|------|
| P2-1 | Hermes adapter ADR | [x] ADR-002 |
| P2-2 | Hermes 最小 session | [x] Mock hermes project + flavor reply |
| P2-3 | AgentCapability 探测 | [x] Project capabilities → Chat toolbar gate |
| P2-4 | 附件（可选） | [x] Bridge images/files + attach demo UI |
| P2-5 | 多服务器 profile | [x] Secure multi-profile store + Connect UI |
| P2-6 | 安全加固 | [x] TLS warn + redaction helpers + secure multi-token keys |
| P2-7 | 内测包 | [x] docs/guides/release.md checklist |
| P2-8 | 自研 Host 兼容层 | [x] docs/guides/self-host-compat.md + Mock subset |

## P3 — 增强

- [ ] 终端独立通道（远期）  
- [x] Skills/MCP 只读浏览（Mock GET /skills + App Skills 页）  
- [x] 设备配对（配对文本/URI；真 QR 渲染可后置）  

## 措辞约束（给贡献者）

- 产品路径只写 **HuanHermes Host / Mock / 自研兼容**  
- 禁止把外部宿主项目写成安装依赖或默认运行时  
