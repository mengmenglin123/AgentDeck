# 连接真实 Host（用户操作指南）

本指南教你把 **HuanHermes App** 连到**你自己服务器上已有的** Host（例如自建的 cc-connect 兼容 Bridge + Management）。

> **重要**
>
> - LiveAgent / cc-connect 是**协议与 UX 参考**，不是依赖、也不是要部署进本仓库的拷贝。
> - **不要**为了本 App 去改 Host 上的 provider、渠道、代理或密钥。
> - 本仓 Mock Host 用于开发；真连时只在 **App 连接页**填写地址与 token。

## 你需要的信息（从你的 Host 配置里抄，不要提交 git）

| 项 | 含义 | 常见默认 |
|----|------|----------|
| Host | 服务器 IP / 域名 | 手机与服务器同网，或经你自己的隧道 |
| Bridge 端口 | WebSocket | 常见 `9810` |
| Management 端口 | HTTP REST | 常见 `9820` |
| Bridge token | WS 鉴权 | Host `[bridge] token` |
| Mgmt token | REST 鉴权 | Host `[management] token` |

## App 操作

1. 打开 **Connect** 页。
2. 填 Host / 端口 / TLS（公网建议 TLS 反代）。
3. 粘贴 Bridge + Mgmt token（写入安全存储，不进 git）。
4. 点连接 → 成功后进 **Sessions**。
5. 选择 project（对应服务器上 Claude Code / Codex 等 agent 项目）→ 新建或进入会话 → **Chat**。

## 验收清单

- [ ] Status 显示 Host 版本 / projects
- [ ] 能列出 sessions（project 方言或 flat 方言均可）
- [ ] 发消息有流式或完整 reply
- [ ] 权限按钮（若 Host 下发 buttons）可点
- [ ] mode/model/dir/stop 以 slash 或工具栏发出（Host 若不支持则显示其错误文案）

## 本仓 Mock 开发

```bash
# 若本机 9810/9820 已被其他进程占用，换端口，勿杀业务 Host
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 python3 server/mock-host/mock_host.py
```

## 故障

| 现象 | 处理 |
|------|------|
| 401 | token 错误；在 App 重填，不改 Host 渠道 |
| 会话 404 | 旧客户端只打 `/sessions`；请升级 App（已自动探测 project 路径） |
| 能连不能聊 | Bridge token / 防火墙 / 未 register；看 App 审计日志（已脱敏） |
