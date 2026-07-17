# HuanHermes App

在手机 / 平板 / 桌面客户端上，**安全连接你自己的服务器**，远程操控：

- **Claude Code**
- **Codex**
- **Hermes**（二期适配）
- 以及其它可挂到 Host 上的 Coding Agent

> 私有仓库 · 个人自建环境 · 不在客户端内重写完整 agent loop。

---

## 架构一句话

| 层 | 策略 |
|----|------|
| **App UI** | 信息架构与流式事件语义参考 [LiveAgent](https://github.com/Stack-Cairn/LiveAgent) |
| **服务器 Host** | Phase 1 兼容 [cc-connect](https://github.com/chenhg5/cc-connect) 的 **Bridge WebSocket** + **Management REST** |
| **Agent 执行** | 在服务器上驱动真实 CLI（不把 API Key 放进 App） |

```text
App  ──WSS Bridge + HTTPS Mgmt──►  Host (cc-connect or mock)
                                      ├─ claude-code project
                                      ├─ codex project
                                      └─ hermes (later)
```

详见 [docs/adr/001-architecture.md)
- [ADR-002 Hermes adapter](docs/adr/002-hermes-adapter.md](docs/adr/001-architecture.md)
- [ADR-002 Hermes adapter](docs/adr/002-hermes-adapter.md)。

---

## 仓库结构

```text
huanhermes-app/
├── apps/mobile/              # Flutter Android 客户端（Connect / Sessions / Chat）
├── packages/huan_protocol/   # Bridge/Mgmt 协议模型与参考客户端（Python）
├── server/
│   ├── mock-host/            # 本地 Mock：Bridge + Management
│   └── examples/             # cc-connect 示例 config
├── docs/
│   ├── AGENT_PROMPT.md       # 给 AI/协作者的主提示词
│   ├── TASKS.md              # 任务板 P0–P3
│   ├── adr/                  # 架构决策
│   └── protocol/             # 协议子集
└── CHANGELOG.md
```

---

## 快速开始（Mock Host）

需要 **Python 3.10+**（仅标准库）。

```bash
# 终端 1：启动 Mock Host（Bridge :9810，Management :9820）
cd server/mock-host
python3 mock_host.py

# 终端 2：跑协议自测
cd packages/huan_protocol
python3 -m test.test_bridge_client

# 终端 2：用参考客户端发一条消息
python3 -m src.bridge_client_demo
```

默认 token（仅本地开发，务必修改）：

| 用途 | 默认值 |
|------|--------|
| Bridge | `dev-bridge-token-change-me` |
| Management | `dev-mgmt-token-change-me` |

环境变量见根目录 `.env.example`。

### 真机 Host（Phase 1）

1. 在服务器安装 [cc-connect](https://github.com/chenhg5/cc-connect) 与 Claude Code / Codex CLI 并完成登录。  
2. 参考 [server/examples/config.example.toml](server/examples/config.example.toml) 启用 `bridge` 与 `management`。  
3. 用 App 或 `packages/huan_protocol` 客户端连接 `wss://your-host:9810/bridge/ws`。

---

## 移动端（Flutter Android）

```bash
# 终端 1：Mock Host
python3 server/mock-host/mock_host.py

# 终端 2：App（需本机 Flutter 3.x + Android SDK）
cd apps/mobile
flutter pub get
flutter run
# 或
flutter build apk --debug
```

应用 ID：`com.huanmeng.huanhermes`。Connect 保存 token；Sessions/Chat 走 Mgmt + Bridge 流式与权限按钮；Chat 工具栏支持 mode/model/dir/stop、重连与审计日志（对齐 LiveAgent 控制台体验）。

## 安全原则

- Token 只存系统安全存储；日志脱敏。  
- Host 上的 Agent 权限极高：**禁止默认公网 YOLO**。  
- 网关 / App **不持有** 模型主 API Key（Key 留在服务器 CLI / env）。  
- 仅连接你明确授权的自建 Host。

---

## 文档

- [连接真实 Host](docs/guides/connect-real-host.md)（只在 App 填 token，不改服务器渠道）
- [LiveAgent 能力对照](docs/roadmap-liveagent-parity.md)


| 文档 | 说明 |
|------|------|
| [docs/TASKS.md](docs/TASKS.md) | 开发任务板 |
| [docs/AGENT_PROMPT.md](docs/AGENT_PROMPT.md) | 后续开发主提示词 |
| [docs/protocol/bridge-subset.md](docs/protocol/bridge-subset.md) | Bridge 兼容子集 |
| [docs/protocol/management-subset.md](docs/protocol/management-subset.md) | Management API 子集 |

---

## License

MIT（见 [LICENSE](LICENSE)）。  
上游参考项目各自保留其 License；本仓库不内嵌其专有代码。


## Guides

- [Connect real Host](docs/guides/connect-real-host.md)
- [Release / 内测](docs/guides/release.md)
- [Self-host compat](docs/guides/self-host-compat.md)
- [Security](docs/security.md)
