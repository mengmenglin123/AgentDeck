
## 扩展（0.5.0，capability `extensions` / `extensions_write`）

- `GET /skills?project=` 额外列出 Agent 自己目录里的技能（`scope`: project/user，`path`，`editable`）；`GET /skills/<name>?project=` 返回 SKILL.md 内容（≤64 KB）。
- `GET /mcp?project=` 额外列出 Agent 配置里的 MCP（`kind` stdio/http/sse，`target`，`scope`，`secret_keys` 只给键名不给值，`editable`，`tools` 为最近一次探测结果）。
- 仅 `extensions_write`（Host 配置 `[workspace] extensions_write = true`）：
  - `POST /mcp?project=` `{name, kind, command, args[], env{}, url, headers{}}` → 写入项目 `.mcp.json`（Codex 写 `~/.codex/config.toml`）
  - `DELETE /mcp/<name>?project=`、`POST /mcp/<name>/probe?project=` → `{tools:[{name, description}]}`（initialize + tools/list，15 s 超时）
  - `POST /skills?project=` `{name, description, body}`、`DELETE /skills/<name>?project=`（只限项目技能）
