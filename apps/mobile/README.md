# Mobile App

Flutter / React Native 客户端将放在此目录。

## 当前状态

- P0 协议与 Mock Host 已在仓库根 `packages/`、`server/` 就绪。  
- 下一步（P0-7+）：

```text
flutter create . --project-name huanhermes_app
# 依赖: web_socket_channel, dio, flutter_secure_storage, riverpod...
```

### 建议页面

1. **Connect** — host / ports / tokens（secure storage）  
2. **Projects** — 来自 Management `/projects`  
3. **Sessions** — 列表 / 新建  
4. **Chat** — Bridge 流式 + 权限按钮  
5. **Settings** — profile、默认 agent  

协议实现可先通过 HTTP/WS 直接对接 Mock，或移植 `packages/huan_protocol` 思路到 Dart。
