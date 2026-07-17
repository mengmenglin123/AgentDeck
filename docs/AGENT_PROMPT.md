# Agent 协作提示（本仓库）

## 产品

HuanHermes = **移动控制台**，连接 **HuanHermes Host**（Mock 或自研实现本仓协议），操控服务器侧 Agent。

## 硬约束

1. **只改本仓库**。不要部署/修改/杀死用户机器上已有的第三方宿主服务。
2. **不把外部项目当依赖**。协议与 UX 可对照开源灵感，但实现、文档默认路径、安装步骤必须是 **HuanHermes 自有**。
3. **禁止** 整仓拷贝外部 Agent 桌面端或 CLI 宿主源码。
4. 凭证不进 git、不进对话明文。
5. 任务以 `docs/TASKS.md` 为准；小步 commit + CHANGELOG。

## 协议

- 规范源：`docs/protocol/*`（本仓拥有）
- 参考实现：`server/mock-host/mock_host.py`
- 客户端：`packages/huan_protocol` + `apps/mobile`

## 措辞

| 禁止 | 改为 |
|------|------|
| 「安装/真连某外部上游宿主」 | 「连接实现本仓协议的 Host / Mock」 |
| 「某某产品方言」 | 「project-scoped 会话路径 / flat 会话路径」 |
| 「依赖某桌面控制台项目」 | 「控制台 UX 自研；实现为本仓 Flutter」 |

## 联调端口

Mock 默认可用环境变量改端口，避免与用户机器上其他服务冲突。
