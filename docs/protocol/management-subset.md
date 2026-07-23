# Management 协议子集（HuanHermes 拥有）

规范源：**本文件**。

鉴权：`Authorization: Bearer <mgmt_token>`。  
Base：`http(s)://host:mgmt_port/api/v1`。

## 通用信封

```json
{ "ok": true, "data": { } }
```

错误：`{ "ok": false, "error": "..." }` + HTTP 状态。

## 会话路径双方言

| 方言 id | 路径 | 说明 |
|---------|------|------|
| **project** | `/projects/{name}/sessions` | 按项目作用域 |
| **flat** | `/sessions?project=` | 扁平列表 |

App 客户端自动探测，无需用户选择。

## 端点

| Method | Path | 说明 |
|--------|------|------|
| GET | `/status` | version / uptime |
| GET | `/projects` | 项目列表，可含 `agent_type`, `capabilities[]` |
| GET | `/projects/{name}` | 项目详情 |
| GET/POST/DELETE | `/sessions` 或 project 作用域 | 会话 CRUD |
| GET | `/sessions/{id}` | transcript / mode / model / workdir |
| GET | `/agents?project=` | 可选；按项目作用域返回 agent id/对象 |
| GET | `/skills?project=` | 可选、按项目作用域的 Skills 目录只读 |
| GET | `/mcp?project=` | 可选、按项目作用域的 MCP 目录只读 |
| GET | `/pairing` | 可选，**无 secrets** |
| GET | `/workspace?path=` | 可选只读工作区浏览（dir listing / file content） |
| GET | `/workspace/git` | 可选只读 git 状态摘要 |
| GET | `/workspace/diff?path=` | 可选只读 unified diff（`path` 空=文件索引） |
| GET | `/memory?project=&scope=&q=` | 可选只读 Host 记忆目录；传 project 时仅返回该 Agent 项目与 global 记忆 |
| GET | `/cron` | 可选只读 Host 定时任务 |
| GET | `/activity?limit=` | 可选只读 Host 活动事件流 |

当前子集**不包含** Workspace/Git 写操作；App 不得暴露 commit/push/pull。未来若开放，必须先增加 ADR、capability、权限模型和协议测试。

## Project capabilities（可选）

```json
"capabilities": ["stream", "buttons", "cancel", "workdir", "mode", "model", "tools_visible"]
```

App 据此隐藏不支持的工具栏项。

## Agent 目录作用域

Memory 请求也接受 `project` 参数；global 记忆可共享，project-scoped 记忆必须与当前 Agent 项目匹配。

`/projects/{name}` 可声明 `models[]` 与 `channels[]`。当 App 传入 `?project={name}` 时，Host 必须只返回该项目可用的 Skills、MCP、Agents 和模型渠道目录，不能返回其它项目的缓存或默认目录。

Production Host 的只读目录配置可来自每个项目的 `models`、`channels`、`skills`
与 `mcp_servers`。`/skills`、`/mcp`、`/agents` 收到未知 `project` 时必须返回 404，
不得静默回退到默认项目；省略 `project` 时才允许使用 Host 明确配置的默认项目。
Bridge 与 Management 必须使用不同 token，Management 响应不得包含任一 token 或
Agent 命令 argv。
