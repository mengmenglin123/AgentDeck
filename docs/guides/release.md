# 内测包 / 发布清单（P2-7）

## 构建（开发者本机）

```bash
cd apps/mobile
flutter pub get
flutter test
flutter build apk --release
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

> 本仓库 CI/服务器可能无完整 Flutter SDK；**内测 APK 在有 SDK 的机器上构建**。

## 联调前置

1. 启动 Mock（**不要占用线上 9810/9820**）:

```bash
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 \
HUAN_BRIDGE_TOKEN=dev-bridge-token-change-me \
HUAN_MGMT_TOKEN=dev-mgmt-token-change-me \
python3 server/mock-host/mock_host.py
```

2. App Connect 填 host / 端口 / token（模拟器用 `10.0.2.2`）。
3. 真 Host：只在 App 填用户自有 token，**禁止改服务器渠道配置**。

## 验收清单

- [ ] Connect 多 profile 切换需重新 Test
- [ ] Sessions 按 project 过滤（含 hermes）
- [ ] Chat 流式 / stop / /perm / attach demo
- [ ] Skills 只读列表（Mock）
- [ ] Pairing 文本可复制（无 token）
- [ ] 审计页无明文 token

## 版本

见 `apps/mobile/pubspec.yaml` 与根 `CHANGELOG.md`。
