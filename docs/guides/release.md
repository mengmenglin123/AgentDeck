# 内测包 / 发布清单

## 构建

原生 App 只在 CI 构建（`.github/workflows/native-apk.yml`）：

- 推送到 `native-android`：构建 APK，产物为 workflow artifact `huanhermes-native-<版本>-apk`。
- 推送 tag `native-v<版本>-rc<N>`：额外发布私有预发布。
- 版本号：`apps/android/app/build.gradle.kts` 中的 `nativeVersionName` / `nativeVersionCode`（2000 起）。
- 签名：预发布密钥不再入库。CI 从 Actions Secrets `HH_SIGNING_P12_B64`（p12 的 base64）和 `HH_SIGNING_PASSWORD` 解码到 `apps/android/signing/huanhermes-prerelease.p12`（与旧 Flutter 版同证书，SHA-256 前缀 `fb220e0970ca5764`）；没有 Secrets 时用 debug 签名。
- Host companion 由 `:app:bundleCompanion` 调用 `scripts/build_companion.sh` 从当前 `server/` 可复现打包进 APK。

本地（无 Android SDK）可跑：

```bash
cd apps/android && gradle -PcoreOnly :core:test
./scripts/check.sh   # Python 协议 / Host 测试
```

模拟器 UI 测试：`.github/workflows/native-emulator.yml`（API 26 + 34，对接 Mock Host 10.0.2.2）。

## 联调前置

1. 启动 Mock（**不要占用线上 9810/9820**）:

```bash
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 \
HUAN_BRIDGE_TOKEN=dev-bridge-token-change-me \
HUAN_MGMT_TOKEN=dev-mgmt-token-change-me \
python3 server/mock-host/mock_host.py
```

2. App 添加 Host（模拟器用 `10.0.2.2`），或用 `production_host.py pair` 生成一次性配对码 / 二维码。
3. 真 Host：只在 App 填用户自有 token；**禁止**为联调改服务器无关服务/渠道配置。

## 真机验收清单

- [ ] 从旧 Flutter 版覆盖安装，Host 与会话保留
- [ ] 扫码配对、证书指纹固定
- [ ] 同局域网自动发现 Host
- [ ] UnifiedPush（ntfy）审批通知，通知内允许/拒绝
- [ ] SSH 一键安装 companion
- [ ] 终端 vim/less、Diff、Workspace

## 版本

见 `apps/android/app/build.gradle.kts` 与根 `CHANGELOG.md`。
