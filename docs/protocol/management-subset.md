# Management API 子集（HuanHermes 兼容）

> 对齐 [cc-connect Management API](https://github.com/chenhg5/cc-connect/blob/main/docs/management-api.md) 的 **MVP 子集**。

## Base

```text
http://<host>:<port>/api/v1
Authorization: Bearer <MGMT_TOKEN>
```

默认开发端口：`9820`。响应 envelope：

```json
{ "ok": true, "data": { } }
{ "ok": false, "error": "message" }
```

## MVP 端点

| Method | Path | 说明 |
|--------|------|------|
| GET | `/status` | 版本、uptime、projects 数量 |
| GET | `/projects` | 项目列表（agent 类型） |
| GET | `/projects/{name}` | 项目详情 |
| GET | `/sessions` | 可选：query `project=` |
| POST | `/sessions` | 创建会话（若 Host 支持） |
| DELETE | `/sessions/{id}` | 删除会话 |

Mock Host 实现上述路径的可运行子集，字段以 mock 为准，真连上游时以 cc-connect 文档为准。
