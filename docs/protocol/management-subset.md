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
| GET | `/agents` | 可选 |
| GET | `/skills` | 可选只读 |
| GET | `/pairing` | 可选，**无 secrets** |

## Project capabilities（可选）

```json
"capabilities": ["stream", "buttons", "cancel", "workdir", "mode", "model", "tools_visible"]
```

App 据此隐藏不支持的工具栏项。
