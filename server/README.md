# Server / Host

## Mock Host（本地开发）

```bash
cd mock-host
python3 mock_host.py
```

| 服务 | 默认 |
|------|------|
| Bridge WS | `ws://127.0.0.1:9810/bridge/ws` |
| Management | `http://127.0.0.1:9820/api/v1` |
| Tokens | 见根目录 `.env.example` |

权限演示：向 Bridge 发送内容 `/perm` 会收到 allow/deny 按钮。

## Phase 1：cc-connect

1. 安装 [cc-connect](https://github.com/chenhg5/cc-connect) 与 Claude Code / Codex，并完成 CLI 登录。  
2. 参考 [examples/config.example.toml](examples/config.example.toml)。  
3. 启用 `bridge` + `management`，用防火墙 / Tailscale 限制来源。  
4. App 使用 **WSS** 与强随机 token。

## 安全

- Agent 可执行 shell / 写文件：token 泄露 ≈ 服务器沦陷。  
- 生产禁止默认 `yolo` / `bypassPermissions`。  
- 不要把 API Key 配进 App。
