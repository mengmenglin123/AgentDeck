# 安全约定（P2-6）

## App

- Bridge / Mgmt token 只进 `FlutterSecureStorage`（按 profile 分 key）
- 非密钥配置进 SharedPreferences
- 日志 / SnackBar / 审计：`Security.redactText` 脱敏
- 非本地 Host 且未开 TLS：Connect 页警告（不强制阻断 LAN）
- 切换 profile **不**静默 ready，需重新 Test & connect

## 仓库

- 禁止提交真实 token / provider key
- `.env.example` 仅本地默认占位
- **禁止**为联调修改用户已部署 Host 的渠道 / 代理 / API key

## Host

- 用户自管 Bridge/Mgmt token 轮换
- 公网务必 TLS 反代
