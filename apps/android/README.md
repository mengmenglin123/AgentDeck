# HuanHermes 原生安卓版（Kotlin + Jetpack Compose）

与已下线的 Flutter 版同 applicationId `com.huanmeng.huanhermes`、同签名，versionCode 从 2000 起，可直接覆盖安装 Flutter 版（需 Android 8.0+ / API 26）。

## 模块

- `core/`：纯 Kotlin/JVM（不依赖 Android）。协议帧与出站构造（对齐 `docs/protocol/schema`）、`BridgeClient`（v2 协商、无上限指数退避、仅鉴权失败停止、心跳判活、seq 去重、resume/resync）、`MgmtClient`、会话转写 reducer、按 Host+session 归属的离线队列、`ChatSession`、Host profile / 会话列表竞态保护、令牌脱敏。
- `app/`：Compose UI、ViewModel、加密 profile 存储（EncryptedSharedPreferences，Keystore 丢失自动重置）。

## 构建与测试

- 仅核心（任何有 JDK 17 的机器，含 arm64）：`gradle -PcoreOnly :core:test`
  - 契约测试读取 `docs/protocol/schema`；若有 `python3`，还会启动 `server/mock-host/mock_host.py` 跑端到端测试。
- 完整：`gradle :core:test :app:testReleaseUnitTest :app:assembleRelease`（Gradle 8.11.1，JDK 17，Android SDK 35）
- Host 端：`cd server && python3 -m unittest discover -p 'test_*.py'`（`pip install jsonschema` 后 Schema 校验更严格）
- CI：`.github/workflows/native-apk.yml`；推 `native-v<版本>-rc<N>` 标签会把 APK 发到本仓库的 prerelease
