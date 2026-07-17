# Management API 子集（HuanHermes 兼容）

> **参照** [cc-connect Management API](https://github.com/chenhg5/cc-connect/blob/main/docs/management-api.md) 的形状，**不**修改任何已部署 Host。
> App / 参考客户端在本仓实现；用户在 App 内填 host/port/token 连接**自己的** Host。

## Base

```text
http://<host>:<port>/api/v1
Authorization: Bearer <token>
```

响应 envelope：

```json
{ "ok": true, "data": { } }
{ "ok": false, "error": "message" }
```

## 双方言（客户端自动探测）

| 方言 | 路径 | 典型实现 |
|------|------|----------|
| **flat**（Mock MVP） | `GET/POST /sessions` · `DELETE /sessions/{id}` | 本仓 Mock Host |
| **project**（cc-connect 形状） | `GET/POST /projects/{name}/sessions` | 真 cc-connect 等 |

客户端顺序：若已知 project，先试 project-scoped；404 再回退 flat。创建会话时若 Host 要求 `session_key`，客户端生成 `huanhermes-app:{project}:{id}`。

## 端点

| Method | Path | 说明 |
|--------|------|------|
| GET | `/status` | 版本、uptime、projects |
| GET | `/projects` | 项目列表（`agent_type`: claudecode / codex / hermes…） |
| GET | `/projects/{name}` | 项目详情 |
| GET | `/projects/{name}/sessions` | **cc-connect 形状** 会话列表 |
| POST | `/projects/{name}/sessions` | body 含 `session_key`（可选生成） |
| GET | `/sessions` | **flat** 会话列表，`?project=` |
| POST | `/sessions` | **flat** 新建 |
| GET | `/sessions/{id}` | 详情 + 可选 transcript |
| DELETE | `/sessions/{id}` | 删除 |
| GET | `/agents` | 可选：支持的 agent / platform 名 |

## 安全

- Token 只存在于用户设备安全存储 / 本机 env，**禁止**提交仓库。
- 不在文档或日志中打印真实 token。
- **不要**为了联调去改线上 Host 的 provider / 渠道配置。
