# HuanHermes

**远程控制台 App**：在手机上管理会话，驱动**你服务器上的** Claude Code / Codex / Hermes（二期）Agent。  
App **不做** coding agent loop；真相源在服务器 Host。

## 产品原则

1. **本仓自有** Bridge WebSocket + Management REST 协议子集（见 `docs/protocol/`）。
2. **Mock Host**（`server/mock-host`）是一等公民参考实现与联调环境。
3. **自研 Host** 只需实现本仓协议即可对接（见 `docs/guides/self-host-compat.md`）。
4. 外部开源项目（桌面控制台 UX、CLI 宿主协议形状）仅作**设计灵感**，**不是依赖、不是运行时、不是安装步骤**。
5. 禁止把第三方 Host 源码拷进本仓；禁止为联调修改用户已部署服务的渠道/密钥。

## 架构

```
App (Flutter Android)  ──WSS Bridge + HTTPS Mgmt──►  Host (Mock 或自研兼容实现)
                                                      └── 驱动服务器侧 Agent 进程
```

| 层 | 说明 |
|----|------|
| **App** | 连接配置、多 Host profile、会话列表、流式聊天、权限、工具栏、审计 |
| **协议** | `docs/protocol/bridge-subset.md` + `management-subset.md` |
| **Mock Host** | 可演示全流程（流式 / cancel / mode / hermes project / skills / pairing） |
| **Agent** | 服务器侧 Claude Code / Codex / Hermes — **不在 App 内重写** |

## 仓库结构

```
apps/mobile/              # Flutter Android 控制台
packages/huan_protocol/   # Python 协议参考客户端 + 测试
server/mock-host/         # Mock Host（默认端口见环境变量）
docs/protocol/            # 协议规范（本仓拥有）
docs/guides/              # 连接 / 发布 / 自研 Host
docs/adr/                 # 架构决策
```

## 快速开始（Mock，推荐）

```bash
# 开发机：任意空闲端口（示例 19810/19820）
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 HUAN_BRIDGE_TOKEN=dev-bridge-token-change-me HUAN_MGMT_TOKEN=dev-mgmt-token-change-me python3 server/mock-host/mock_host.py

cd apps/mobile && flutter pub get && flutter test && flutter run
# 模拟器 Host 填 10.0.2.2，端口与上面一致
```

## 连接你自己的 Host

1. 在服务器跑 **实现本仓协议** 的 Host（Mock 或自研）。  
2. 在 App Connect 页填 host / 端口 / token。  
3. 详见 [connect-real-host.md](docs/guides/connect-real-host.md)。

**不要**把「安装某个外部宿主项目」当作本产品的前置条件。

## 文档

- [任务板](docs/TASKS.md)
- [ADR-001 架构](docs/adr/001-architecture.md)
- [ADR-002 Hermes adapter](docs/adr/002-hermes-adapter.md)
- [Bridge 协议子集](docs/protocol/bridge-subset.md)
- [Management 协议子集](docs/protocol/management-subset.md)
- [控制台能力路线图](docs/roadmap-console-parity.md)
- [连接真实 Host](docs/guides/connect-real-host.md)
- [内测 / 发布](docs/guides/release.md)
- [自研 Host 兼容](docs/guides/self-host-compat.md)
- [安全](docs/security.md)

## 版本

见 `CHANGELOG.md` · App `apps/mobile/pubspec.yaml`
