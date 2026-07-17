# ADR-002: Hermes Agent Adapter（二期）

- **状态**: Accepted（设计冻结；实现可渐进）  
- **日期**: 2026-07-17  
- **关联**: [ADR-001](001-architecture.md)、`docs/protocol/*`  
- **约束**: LiveAgent / cc-connect 仅作**协议与 UX 参照**；**不**修改用户已部署的 Host 配置/渠道。

## 背景

HuanHermes App 是**远程控制台**，要操控用户服务器上的：

| Agent | 一期路径 | 二期 |
|-------|----------|------|
| Claude Code | 经 Host（cc-connect 兼容）CLI 驱动 | 保持 |
| Codex | 同上 | 保持 |
| **Hermes Agent** | 未接入 | **本 ADR** |

Hermes 自有 Gateway / CLI / 会话模型，与 Claude/Codex 不同，不能假设与 cc-connect 内部 agent_type 一一同构。

## 决策

### 1. 对外统一仍是「Bridge + Management」

App **只**讲：

- Management REST：projects / sessions / status  
- Bridge WebSocket：message / reply_stream / buttons / cancel …

Hermes 适配发生在 **Host 侧**（用户服务器上的适配层），App 不嵌入 Hermes SDK、不跑 agent loop。

### 2. Hermes 在 Host 上的两种合法形态

| 形态 | 说明 | 推荐 |
|------|------|------|
| **A. 兼容 Host 的 `agent_type=hermes`** | 已有 Host（如自建 cc-connect 兼容层）增加 hermes 驱动 | 有现成 Host 时 |
| **B. 自研 Huan Host Hermes adapter** | 本仓 `server/` 未来实现最小 Host，只服务 App | 长期可控 |

MVP 二期先定 **能力契约**，两种形态共用同一 App 协议。

### 3. Project 命名约定

- `agent_type`: `hermes`  
- project `name`: 建议 `hermes` 或 `hermes-<profile>`  
- session_key: `{platform}:{scope}:{id}`，platform 对 App 为 `huanhermes-app`

Mock Host 已预置 `hermes` project，供 UI / 列表联调，**不**代表真 Hermes 进程。

### 4. AgentCapability 探测（P2-3）

Management `GET /projects/{name}` 或 `GET /agents` 可返回能力位（渐进）：

| capability | 含义 | App 行为 |
|------------|------|----------|
| `stream` | reply_stream | 流式 UI |
| `buttons` | 权限卡片 | 显示审批条 |
| `cancel` | cancel / stop | Stop 按钮 |
| `workdir` | dir 切换 | 工具栏 dir |
| `mode` | plan/default/yolo… | mode 菜单 |
| `model` | 模型切换 | model 菜单 |
| `tools_visible` | thinking/tool 事件 | 折叠工具区 |
| `terminal` | 独立终端（P3） | 隐藏直到支持 |
| `skills_readonly` | Skills 浏览（P3） | 隐藏直到支持 |
| `memory` | 记忆面板（Hermes） | 二期后 |

未知能力：**降级**（隐藏控件），不崩溃。

### 5. Hermes 特有映射（Host 内部）

Host adapter 负责：

```
App Bridge message  →  Hermes session prompt / gateway run
Hermes stream token →  reply_stream delta / full_text
Hermes tool call    →  tool_call / tool_result 事件
Hermes 权限请求     →  buttons + card_action
App cancel          →  Hermes 中断/取消当前 run
```

**禁止**在 App 内直接调用 Hermes 内部 API key / provider 配置。  
用户在 Hermes/Host 侧已有渠道时，App **只**持有 Bridge/Mgmt token。

### 6. 非目标（本 ADR）

- 在 Flutter 内嵌 Hermes Agent  
- 修改用户机器上已运行的 cc-connect / Hermes 渠道与代理  
- 实现完整 MCP 市场、Cron UI（P3）  
- 把 LiveAgent 或 cc-connect 源码拷进本仓  

## 实现阶段

| 阶段 | 交付 | 状态 |
|------|------|------|
| P2-1 | 本 ADR + 能力表 | **本提交** |
| P2-2 | Mock 增强：hermes project 更丰富 transcript；可选 `capabilities` 字段 | 随后 |
| P2-3 | App 按 capabilities 显示/隐藏工具栏 | 随后 |
| P2-8 / 后续 | 真 Hermes 最小 Host adapter 或文档对接用户自建 Host | 未开始 |

## 后果

| 正面 | 负面 |
|------|------|
| App 协议稳定，Hermes 可后置 | 真 Hermes 需 Host 侧开发量 |
| 与 Claude/Codex 同一控制台 UX | 能力差异靠探测，UI 需降级逻辑 |
| 不绑架用户现有渠道配置 | 双 Host 形态要测双方言 Mgmt |

## 验收（Hermes 最小可用时）

1. App 连接用户 Host（token 仅 App 内）  
2. project 列表出现 `agent_type=hermes`  
3. 新建会话 → 发消息 → 有流式或最终 reply  
4. `/perm` 或等价权限可审批  
5. Stop/cancel 能停当前 run（若 capability 声明）  
6. **全程不**改用户 provider/proxy 配置  

## 参考（只读）

- 本仓 `docs/protocol/bridge-subset.md`、`management-subset.md`  
- LiveAgent：控制台与本地真相源分离思想  
- cc-connect：Bridge/Mgmt 形状（**不**拷贝、**不**改用户实例）  
