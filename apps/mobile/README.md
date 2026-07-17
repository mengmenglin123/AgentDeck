# HuanHermes Mobile (Flutter Android)

真实 Flutter Android 工程：连接自建 Host，列会话、聊天流式、权限审批。

## 工程信息

| 项 | 值 |
|----|----|
| Dart package | `huanhermes_app` |
| applicationId | `com.huanmeng.huanhermes` |
| 入口 | `lib/main.dart` |

## 页面

1. **Connect** — host / ports / TLS / tokens（安全存储）
2. **Sessions** — Management `/projects` + `/sessions` 列表 / 新建 / 删除
3. **Chat** — Bridge WebSocket 流式 transcript + 权限按钮

## 目录

```text
lib/
  models/          connection_config, session_info, transcript
  services/        secure store, mgmt, bridge, session/chat controllers
  screens/         connect, sessions, chat
android/           Android 工程
test/              unit + widget tests
```

## 运行

```bash
# 仓库根
python3 server/mock-host/mock_host.py

cd apps/mobile
flutter create . --project-name huanhermes_app --platforms=android   # 仅补齐缺失平台文件
flutter pub get
flutter test
flutter run
```

### 连接 Mock

| 场景 | Host |
|------|------|
| Android 模拟器 | `10.0.2.2` |
| 真机同一局域网 | 电脑局域网 IP |

Ports: Bridge `9810`, Mgmt `9820`  
Tokens: 见仓库 `.env.example`（仅本地）

### 权限演示

在 Chat 发送：`/perm`  
点 Allow / Deny / Allow all → 发送 Bridge `card_action`。

## 安全

- Token → `flutter_secure_storage`
- 日志 / UI 使用 redacted Bridge URL
- 权限必须用户点选（无默认 YOLO）
