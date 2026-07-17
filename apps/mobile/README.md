# HuanHermes Mobile (Flutter Android)

真实 Flutter Android 工程，用于连接自建 Host（cc-connect Bridge + Management，或仓库 Mock Host）。

## 工程信息

| 项 | 值 |
|----|----|
| Dart package | `huanhermes_app` |
| applicationId | `com.huanmeng.huanhermes` |
| 入口 | `lib/main.dart` |
| P0-7 | Connect 页 + 安全存储 + Mgmt `/status` 探测 |

## 目录

```text
lib/
  main.dart
  app.dart
  models/connection_config.dart
  services/
    connection_store.dart
    secure_config_store.dart   # tokens → secure storage
    mgmt_client.dart
    connection_controller.dart
  screens/
    connect_screen.dart
    status_screen.dart
  errors/app_errors.dart
android/                       # 可打开的 Android 工程
test/                          # 单元测试
```

## 运行

前置：Flutter 3.22+、Android SDK、本机可访问 Host。

```bash
# 仓库根目录启动 Mock
python3 server/mock-host/mock_host.py

cd apps/mobile
# 若缺少 gradle-wrapper.jar 等平台文件，先补齐（不覆盖 lib/）：
flutter create . --project-name huanhermes_app --platforms=android
flutter pub get
flutter test
flutter run
flutter build apk --debug
```

默认 Mock（仅本地，见仓库 `.env.example`）：

- Host `10.0.2.2`（Android 模拟器访问宿主机）或真机局域网 IP
- Bridge `9810` / Mgmt `9820`
- Token：`dev-bridge-token-change-me` / `dev-mgmt-token-change-me`

**模拟器访问宿主机 Mock：** Host 填 `10.0.2.2`（Android 模拟器）。  
**真机：** 填电脑局域网 IP，并确保防火墙放行 9810/9820。

## 安全

- Token 写入 `flutter_secure_storage`（Android EncryptedSharedPreferences）
- 非密钥配置写入 `shared_preferences`
- UI/日志使用 redacted Bridge URL（`token=***`）
- 禁止把默认 dev token 用于公网 YOLO

## 下一步

- P0-8 会话列表 + 聊天流式
- P0-10 UI 权限 allow/deny/allow_all 按钮
