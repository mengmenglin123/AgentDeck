# AgentDeck

**在手机上指挥你服务器上的 AI 编程 Agent。**

AgentDeck（原名 HuanHermes）是一个原生 Android 应用（Kotlin + Jetpack Compose），配一个装在服务器上的轻量 Host。手机负责看、批、聊；真正干活的 Claude Code / Codex / Hermes 留在你自己的服务器上，代码和密钥都不离开你的机器。

[⬇️ 下载最新 APK](https://github.com/mengmenglin123/AgentDeck/releases/latest) · [协议文档](docs/protocol/) · [发布记录](CHANGELOG.md)

---

## 能做什么

**会话与聊天**
- 多 Host 配置，扫码配对（一次性配对码 → 每台设备独立 token），mDNS 自动发现，证书固定
- 会话列表：状态、预览、置顶、排序、紧凑模式
- 流式聊天，Markdown / 代码高亮，回合折叠，取消、模式与模型切换，斜杠命令，@ 文件引用
- 附件（图片、拍照、文件）、草稿、发送队列、离线排队自动重发
- 计划卡片、用量统计、朗读回复

**审批闭环**
- 「需要我」收件箱：所有 Host 上等待你决定的权限请求集中在一处
- 通知栏直接允许 / 拒绝，UnifiedPush 推送，后台轮询兜底，桌面小部件和快捷设置磁贴
- 敏感操作可要求指纹 / 锁屏验证

**查看与操作服务器**
- Workspace 浏览、Git 状态与 Diff、Diff 行评论，可选的 Git 写操作（需 Host 显式开启）
- 内置终端（自研 VT100 模拟）
- Agents、Skills、MCP、Cron、Memory、Activity、Logs、Audit、Status、Dashboard
- 扩展管理：发现 Claude / Codex / Hermes 的 MCP 服务器与技能，添加、删除、探测工具，10 个常用连接器预设

**本地 Agent**
- 不装 Host 也能用：在手机上直接配置大模型供应商（OpenAI、DeepSeek、通义千问、Kimi、智谱、OpenRouter、Claude、自定义），拉取模型列表，按供应商选择模型
- 通过 SSH 连接你的服务器执行命令，危险命令需要你批准
- 多对话、流式输出、工具调用卡片

**其它**
- 手机端定时任务（按时给 Agent 发提示词）
- SSH 一键安装 Host companion（tar.gz 资源 + sha256 校验）
- 主题、字号、高对比、等宽聊天，设置导入导出，平板双栏

## 架构

```
手机 App（Kotlin + Compose）
   │  WSS Bridge（流式聊天 / 权限 / 终端）
   │  HTTPS Management REST（目录、文件、Git、扩展…）
   ▼
Host（server/，Python）── 驱动服务器上的 Claude Code / Codex / Hermes 进程
```

- App：Compose + ViewModel + Coroutines/Flow，OkHttp WebSocket，Kotlinx Serialization，加密存储
- 协议本仓自有，见 `docs/protocol/`；v2 新能力按客户端声明的 capability 开启，向后兼容
- `apps/android/core` 是纯 JVM 模块（协议、会话、离线队列、终端等），可脱离安卓单独测试

## 仓库结构

```
apps/android/        原生 Android 应用（app 界面 + core 纯 JVM 逻辑）
server/              Host 实现（production_host.py）与全部测试
server/mock-host/    Mock Host，联调和模拟器测试用
packages/            Python 协议参考客户端
docs/protocol/       协议规范与 JSON Schema
docs/guides/         连接、发布、自研 Host 指南
.github/workflows/   APK 构建与模拟器 UI 测试
```

## 快速开始

**1. 安装 App**：从 [Releases](https://github.com/mengmenglin123/AgentDeck/releases/latest) 下载 APK（Android 8.0+）。

**2. 先用 Mock Host 体验**

```bash
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 \
HUAN_BRIDGE_TOKEN=dev-bridge-token-change-me HUAN_MGMT_TOKEN=dev-mgmt-token-change-me \
python3 server/mock-host/mock_host.py
```

在 App 里添加 Host，填电脑的局域网 IP、两个端口和 token（模拟器里填 `10.0.2.2`）。

**3. 连接真实服务器**：在 App 里用「SSH 一键安装」，或手动运行 `server/production_host.py`，然后 `production_host.py pair` 生成配对二维码扫码即可。详见 [连接真实 Host](docs/guides/connect-real-host.md)。

## 开发

```bash
# core 单元测试（JDK 17 + Gradle）
cd apps/android && gradle -PcoreOnly :core:test

# Host 测试
cd server && python3 -m unittest discover -p 'test_*.py'
```

- 推送到 `native-android` 由 CI 构建 APK；打 `native-v<版本>-rc<N>` 标签会发布预发布版并在 API 26 / 34 模拟器上跑 UI 测试
- 发布签名密钥不在仓库里，CI 从 Actions Secrets（`HH_SIGNING_P12_B64`、`HH_SIGNING_PASSWORD`）读取；没有时自动用 debug 签名，fork 也能构建
- 更多见 [发布指南](docs/guides/release.md)、[自研 Host 兼容](docs/guides/self-host-compat.md)、[安全说明](docs/security.md)

## 许可

[MIT](LICENSE)
