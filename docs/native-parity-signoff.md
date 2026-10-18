# 原生版对齐签核（Flutter 0.1.206 → 原生 0.2.8）

逐项对照 Flutter 版功能，标注原生实现位置与验证方式。✅ = 已实现并有自动化验证；◐ = 已实现，部分需真机/真实 Host 人工验证。

## 连接与配对
| 功能 | 原生实现 | 验证 |
|---|---|---|
| 多 Host profile、测试并保存、切换 | core `hosts/Profiles.kt`、`HostsScreen` | ✅ JVM 测试 + 模拟器 a_ |
| 配对链接导入（huanhermes://connect） | core `HostConfig.parsePairingUri` | ✅ |
| 扫码配对 | CameraX + zxing `ui/pairing/QrScanScreen` | ◐ 需真机相机 |
| 一次性配对码 → 每设备令牌（新） | Host `device_tokens.py` + `/pairing/claim`；core `Pairing` | ✅ Python + JVM + 模拟器（mock 演示码 MOCKPAIR） |
| 设备吊销（新） | `production_host.py pair --revoke`、`DELETE /devices/{id}` | ✅ Python |
| 证书 pinning（自签名可用）（新） | core `net/Pinning.kt`、表单「证书指纹」 | ✅ JVM（HeldCertificate） |
| 局域网发现（新） | Host `mdns_advertiser.py`；App NSD `HostDiscovery` | ◐ Python 单测；需同网真机 |
| SSH 一键安装 companion | core `ssh/CompanionInstaller`（sshlib）、`SshInstallScreen`；安装包构建时由 `scripts/build_companion.sh` 从当前 server/ 打包并内置 sha256 | ◐ 命令/解析/失败路径 JVM 测试；真机需 SSH 服务器 |
| Flutter 数据迁移 | `SecureProfileStorage.migrateFromFlutter` + core `FlutterMigration` | ◐ 解析 JVM 测试；需覆盖安装实测 |

## 会话与聊天
| 功能 | 原生实现 | 验证 |
|---|---|---|
| 会话列表增删改、分组、置顶/归档、状态 | `SessionsScreen`、core `overview/` | ✅ |
| 流式聊天、取消、离线队列、断线补齐 | core `chat/`、`bridge/`（protocol v2 seq/resume） | ✅ JVM + live mock/production |
| Markdown / 代码高亮 / 工具卡 / Diff 卡 | core `render/`、`ui/chat/` | ✅ |
| 权限卡 perm:<id>:<decision> | `ChatScreen`、InboxScreen | ✅ 模拟器 b_ |
| 模式/模型、斜杠命令、@ 文件 | `ChatComposer`、core `Mentions` | ✅ |
| 平板双栏 | `HuanHermesRoot`（≥840dp） | ◐ |

## 通知与后台
| 功能 | 原生实现 | 验证 |
|---|---|---|
| 跨 Host「需要我」收件箱 | `InboxScreen`、core `overview/Inbox` | ✅ |
| 通知内允许/拒绝 | `notify/ApprovalReceiver` | ◐ |
| 后台轮询（WorkManager 15 分钟 + 离开后 9 分钟高频） | `notify/InboxWorker` | ◐ |
| UnifiedPush 实时推送（新） | Host `push_notifier.py`（只带引用）；App `HHPushService` | ✅ Python；◐ 需 ntfy 分发器 |
| 前台服务保持连接（新） | `notify/KeepAliveService` | ◐ |
| FCM | 未做：需要你的 Firebase 项目（google-services.json）与 Host 端 FCM 凭据 | — |

## 工具页
| 功能 | 原生实现 | 验证 |
|---|---|---|
| Status / Dashboard | `DashboardScreen` | ✅ 模拟器 c_ |
| Agents / Skills / MCP / Tools / Memory / Cron | `CatalogScreen` + core `catalog/HostCatalogs` | ✅ JVM + live mock + 模拟器 |
| Activity / Logs / Audit | 同上；Host `host_feeds.py`（生产 Host 新增） | ✅ |
| Workspace 浏览 + 高亮 | `WorkspaceScreen`；Host `workspace_readonly.py` | ✅ 模拟器 |
| Git 状态 + Diff | `GitScreen` | ✅ 模拟器 |
| 终端（PTY） | core `terminal/TerminalEmulator`（VT100/xterm、CJK 宽字符、256 色/真彩、滚动区、备用屏）+ `TerminalSession`；按键栏、Ctrl、整行/实时两种输入 | ✅ JVM + live mock + 模拟器 |

## 设置
主题（自动/浅/深）、动态取色、纯黑、高对比、字号、折叠工具调用、触感、后台审批通知、UnifiedPush、保持连接、保持屏幕常亮、等宽聊天字体、紧凑会话列表、会话排序、仪表盘自动刷新、终端字号、复制本机偏好、恢复默认偏好、隐私说明。
与 Flutter 的有意差异：不提供「重连次数」，原生按审计要求使用无上限指数退避（仅鉴权失败停止）。

## 审计清单（docs/flutter-0.1.206-audit-bugs.md）
1–11 全部覆盖：1（终端 busy：任意 terminal_out 解锁 + 10 s 兜底 + ack 失败清 busy）在 0.2.5/0.2.6；11（通知 intent 保留）在 0.2.4。

## 下掉 Flutter 版
待你确认后执行：删除 `apps/mobile` 与 `.github/workflows/build-apk.yml`，companion 发布流程改为由原生构建打包（已在 0.2.6 实现）。
