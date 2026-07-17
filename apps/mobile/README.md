# HuanHermes Mobile

Flutter Android **控制台** App。连接 HuanHermes Host（Mock 或自研）。

## 开发

```bash
flutter pub get
flutter test
flutter run
```

### Mock Host

```bash
# 仓库根；使用空闲端口
HUAN_BRIDGE_PORT=19810 HUAN_MGMT_PORT=19820 \
HUAN_BRIDGE_TOKEN=dev-bridge-token-change-me \
HUAN_MGMT_TOKEN=dev-mgmt-token-change-me \
python3 server/mock-host/mock_host.py
```

模拟器 Host：`10.0.2.2`。

### 聊天控制

- 工具栏：mode / model / dir / status / stop（按 project capabilities 显隐）  
- 附件 demo、权限按钮、审计日志、Skills、配对文本  

## 安全

Token 进 secure storage；日志脱敏。见 `docs/security.md`。
