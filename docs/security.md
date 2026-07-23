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
- **禁止**为联调修改用户已部署服务的渠道 / 代理 / API key

## Host

- 用户自管 Bridge/Mgmt token 轮换
- 公网务必 TLS 反代


## 附件与通知

- 小附件进入 Bridge 前限制为 5 MB/项、10 MB/消息、最多 4 项
- 附件 base64 不进入离线队列持久化；失败后由用户恢复连接重试
- 通知 payload 只使用会话引用，不包含 token 或附件正文
- Android 不申请旧式全盘读写权限；文件选择走系统 picker

## Host 工作目录策略

- Agent 与 terminal 启动前必须经过 `WorkspaceAllowlist`；只允许配置的 canonical existing roots 及其子目录。
- `Path.resolve(strict=True)` 后再判断 containment，拒绝相对路径、缺失目录、文件、NUL 和 symlink 逃逸。
- `ProductionAgentAdapter` 与 `PtyTerminalAdapter` 都支持注入同一 workdir validator；Bridge resolver 不能绕过 Adapter validator。
- 客户端传入的 `workdir` 只能在 allowlist 内选择，不能改变根目录、argv 或环境密钥。
- allowlist 不能替代 Linux 权限、容器隔离或 TLS；部署仍需最小权限运行 Host 和 Agent。
