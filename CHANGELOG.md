## 0.1.206

- **全新应用图标**：自适应图标（渐变背景 + 羽翼/终端标识，支持 Android 13 单色主题图标），同步更新旧版 mipmap、品牌化启动页、通知小图标与 App 内 Logo。
- **修复消息渲染崩溃**：Markdown 渲染器的代码块/行内正则括号不配对，任何带代码块的消息都会抛出 `FormatException`；已修正并补充渲染测试。
- **修复权限审批无效**：审批按钮改为发送卡片完整动作（`perm:<id>:<decision>`）并携带卡片的 `reply_ctx`，生产 Host 不再拒绝；权限页按钮行展平，修复 `TypeError` 崩溃。
- **通知更准确**：连接时不再误报「出错」通知；按钮帧（权限请求）会正常推送通知；已取消的运行不再提示「任务完成」；桥接握手被拒时立即以认证错误失败。
- **Mock Host 修复**：请求路径按百分号解码，App 编码的会话 ID（`%3A`）可正常查看/重命名/删除；Agent 回复改为在工作线程流式发送，运行中也能处理取消与卡片操作。
- **小屏布局修复（~390dp）**：日志/记忆/活动/差异/工作区/配对/审计页顶栏只保留 3 个图标，其余收进「更多操作」；会话页顶部控件区限高可滚动（键盘弹出不再溢出），项目下拉框长名称省略；连接页「高级选项」行与标题自动省略；加载占位可滚动；会话卡片与连接表单改用 Material 背景，点按水波纹可见。
- **SSH 首次部署更可靠**：核对主机指纹的时间不再计入连接超时（之前确认超过 20 秒就会报「SSH 连接超时」）；拒绝指纹时明确提示「主机指纹未被确认」；同一流程内的发现/安装/初始化固定使用首次确认的主机指纹，指纹变化会中止并警告。
- **配对导入修复**：导入对话框的输入控制器在关闭动画期间被提前释放导致崩溃，已修复；扫码时连续识别同一二维码不再多次返回而关闭连接页；对话框内容可滚动。
- **测试**：新增 SSH Companion 安装/配置与配对导入的服务与界面测试（模拟 SSH 与相机层）、基于真实 dartssh2 与本地 paramiko 服务器的 SSH 适配器端到端测试、390/320dp 键盘弹出布局测试，以及工具中心逐个打开全部工具的端到端测试。

## 0.1.205

- **修复启动卡在启动页**：0.1.204 Release 包在 `runApp` 之前初始化通知插件，使用的小图标 `@mipmap/ic_launcher` 在 Release 构建中并不存在（只有 `@drawable/ic_launcher`，且资源被 R8 压缩），`initialize()` 抛出 `invalid_icon`，导致应用永远停留在白底蓝图标的启动页。
- **启动流程改造**：`main()` 立即 `runApp`，先显示主题化的「正在启动…」页面；连接配置、主题、设置等初始化移到界面之后执行，每一步都有 5 秒超时和兜底，任何插件异常或卡住都不会再阻塞启动。
- **安全存储自愈**：`flutter_secure_storage` 开启 `resetOnError`；若重装后加密配置因系统密钥失效而无法读取，会自动清除并以空配置继续，同时一次性提示「已重置，请重新添加服务器」。
- **通知更稳**：新增单色通知小图标 `ic_stat_notify`（并通过 `res/raw/keep.xml` 防止被资源压缩移除）；通知初始化在后台进行且不会抛错；通知权限改为首个界面显示后再申请；补充 flutter_local_notifications 的 R8/ProGuard 规则。
- **禁止备份应用数据**：`allowBackup="false"`、`fullBackupContent="false"`，并通过 `dataExtractionRules` 排除云备份与设备迁移，避免恢复出无法解密的数据。
- **固定签名**：Release 构建改用仓库内固定的预发布签名（如存在 `android/key.properties` 则优先使用正式密钥），此后的版本可直接覆盖安装。**从 0.1.204 及更早版本升级需先卸载一次**（旧包使用 CI 每次随机生成的 debug 签名）。
- **测试**：新增启动流程测试，覆盖存储初始化抛错、卡住超时、加密存储无法解密三种情况。

## 0.1.204

- **Host 安全修复随 Companion 发布**：重建 `huanhermes-host-0.1.204.tar.gz`（sha256 `28baff5f2df0d371c4aca3770661db913e56c050759fd20ad8271c28c3bbb31a`），包含 token 字节级恒定时间比较、Management `DELETE` 先校验会话归属、`host.toml` 0600 原子写入、启动安全告警与 Mock Host 日志脱敏；App 内 `archiveSha256` 与下载地址同步更新，旧的 0.1.203 包已从资源中移除。
- **可复现打包**：新增 `scripts/build_companion.sh <版本> [日期]`（GNU tar 排序 + 固定 mtime/属主 + `gzip -n`），相同输入得到相同 sha256。
- **流式聊天更顺滑**：`reply_stream`/`thinking` 增量按 ~32 ms 合并刷新，不再每个 chunk 整页重建；最终块与其它帧仍立即刷新；停留在底部时自动跟随最新消息，向上翻阅历史时不打扰。
- **聊天气泡可读性**：气泡颜色改由主题派生（浅色/深色/高对比度一致），行高 1.45、说话方向圆角、平板上最大宽度 720，去掉阴影。
- **连接状态更清晰**：状态点与状态胶囊统一使用主题成功/警告/危险色，并补充无障碍语义；离线空状态提供「重新连接」按钮；修复“已重连主机”提示从未出现的问题，重连提示全部中文化。
- **Material 3 主题补全**：补齐 `tertiaryContainer`、`errorContainer` 等配色（新增 WCAG AA 对比度测试）；权限按钮前景色可读；主题模式显示“跟随系统/浅色/深色”。
- **统一加载/错误状态**：新增 `ConsoleErrorState`、`ConsoleInlineError`，会话、技能、MCP 页面出错时可直接重试；剩余英文标题、提示与排序说明统一为中文；替换已弃用的 `withOpacity`。
- **预发布 APK**：推送 `v<版本>-rc<N>` 标签时由 CI 构建 arm64 Release APK（debug 签名）并附加到本私有仓库的预发布。

## 0.1.200

- **SSH Agent 自动发现**：App 可使用密码或 PEM 私钥登录服务器，并只读识别 Codex、Claude Code 与 Hermes。
- **Host Key 校验**：首次 SSH 探测必须展示并确认服务器指纹；SSH 凭据仅保留在当前页面内存，不写入配置。
- **Driver 映射**：发现结果映射为 `codex_exec_json`、`claude_stream_json`、`hermes_stream_json` 及对应能力目录。
- **安全探测**：远端仅执行固定白名单命令，不使用 sudo、不安装或修改 Agent；长期控制继续通过 Bridge/Mgmt。

## 0.1.199

- **Agent 作用域入口**：主壳层新增共享 Agent/项目选择器，切换时同步刷新会话列表和所有项目目录入口。
- **模型与渠道可见性**：当前 Agent 的模型、渠道和类型显示在全局作用域栏，减少切换后误用旧目录的风险。
- **终端门控**：会话页和 Chat 快捷菜单遵循项目 `terminal` capability；终端标题显示项目、握手状态和 PTY 尺寸。

 - Session contract fix: preserve explicit URL session keys for project-scoped creation.

## 0.1.198

- **Host Driver seam**：新增 Host-owned `JsonlAgentDriver`，将受控 JSONL stdout 映射到现有 Bridge transcript 事件。
- **输出安全**：支持半行/UTF-8/大小上限/坏 JSON/未知事件；session key 与 reply context 由 Host 注入，Agent 输出不能覆盖。
- **验证**：新增 Driver/runtime 回归；Python Server 35 项、协议 17 项、Flutter 44 项全部通过。
- **生命周期**：已退出 stdout 排空、退出码、cancel/timeout、常驻进程多轮 `reply_ctx` 和唯一 `run_done`。
- **路由契约**：新增 `AgentBridgeLoop`，锁定 `message/cancel/ping/poll` 与 fail-closed 错误映射。
- **WebSocket transport**：新增 stdlib handshake、token 鉴权、register 门控、masked frame、poll、连接级 session 回收、ownership 防接管和 shutdown 测试；TLS/部署配置仍待接入。
- **真 PTY terminal**：新增 `PtyTerminalAdapter`/`TerminalBridgeLoop`，覆盖显式 argv、resize、过期 stream、输出排空、退出和取消。
- **Workspace 安全**：新增 `WorkspaceAllowlist`，拒绝相对/缺失/NUL/symlink escape 路径，并注入 Agent/PTY Adapter；Server 回归共 54 项。
- **限制**：尚未绑定 Claude Code、Codex 或 Hermes 的真实 CLI 输出；Android 真机通知集成仍待 Android SDK/CI。

## 0.1.197

- **CatalogState 深 Module**：集中 loader、错误映射、自动刷新、dispose 与过期响应隔离；Skills、MCP、Agents 已迁移。
- **目录配置修复**：Agents 不再持有初始 Host 的旧 `MgmtClient`，切换主机或项目后使用最新配置。
- **通知精确深链**：任务完成与权限通知使用稳定 `session_key`；点击通知可跨项目定位会话并直接进入 Chat。
- **测试**：新增 CatalogState 生命周期、跨项目 session key 定位回归。

## 0.1.196

- **Agent 作用域一致性**：共享 `SessionController`，切换 Claude Code/Codex/Hermes 后会话、Skills、MCP、Agents 与模型目录使用同一项目上下文。
- **Host 目录契约**：Skills/MCP/Agents 支持 `?project=`；项目详情声明 `models[]` 与 `channels[]`，Chat 模型选择由 Host 目录驱动。
- **终端会话强化**：新增 `terminal_open/terminal_open_ack`、`terminal_close` 生命周期，支持 resize stream 关联并拒绝过期 stream 事件；真 PTY 仍属于 Host Adapter。
- **竞态修复**：旧项目刷新请求不能覆盖最新 Agent 选择；新增跨 Agent 回归测试。

# Changelog

## Unreleased（optimize/hark-2026-10）

- **鉴权健壮性**：Bridge/Mgmt token 改为字节级恒定时间比较，非 ASCII token 返回 401 而不是让握手线程崩溃；Mock Host 同步改造并在日志中脱敏 token。
- **会话安全**：Management `DELETE` 先校验会话与项目归属，错误项目的删除请求不再误杀其他项目的运行中会话。
- **Companion 配置**：`host.toml` 以 0600 创建后原子替换，`config/`、`data/` 收紧为 0700。
- **部署告警**：生产 Host 启动时提示占位/过短/共用 token、非回环绑定和配置文件权限过宽（仅告警）。
- **App**：dispose 后忽略迟到的 Bridge 回调；权限卡片正文兼容 `content`/`text`/`title`。
- **DX/CI**：新增 `scripts/check.sh`；回环测试绕过环境代理；CI 增加快速 `python-tests` job。Python Host 测试 105 → 116 项。

## 0.1.195

- **HostCapabilities 深 Module**：
  - 新增 typed `CapabilitySet` / `HostRuntimeInfo`
  - `/status` adapter、Hermes process、Host capability 解析集中管理
  - `ProjectInfo` 与 `ChatController` 共用同一 capability Interface
  - 新增 Mock、兼容 Host、真 Hermes 和 capability 规范化 fixture
  - Flutter 33/33、Python 16/16、analyze error/warning 为零

## 0.1.194

- **协议契约与验证闭环**：
  - Workspace 恢复只读：移除未写入协议且实际 404 的 Git commit/push/pull 入口
  - 新增只读契约回归，协议测试由 15 个增至 16 个
  - CI 增加 `flutter analyze`、`flutter test`、`py_compile`、协议测试和 PR 触发
- **Host 与版本语义**：
  - 正确读取 `/status.hermes.adapter/process`，不再把任意兼容 Host 标成真 Hermes
  - App/Bridge/Python/Mock 版本更新并集中 App 版本常量
- **附件与通知**：
  - 真文件/相册/相机选择统一经 `FilePickerService`
  - 限制单项 5 MB、总计 10 MB、最多 4 项；附件失败不写离线队列
  - 通知点击与冷启动 payload 导航到会话页
- **Android**：移除旧式外部存储权限；AGP 升级留待独立构建验证

## 0.1.193

- **Catalog/日志/筛选中文扫尾**：
  - 日志/审计/记忆/活动：最新/最旧排序 tooltip 中文
  - 日志/审计/MCP/技能/定时/代理/记忆/活动/工作区/会话：FilterChip 显示标签中文
  - 通知「任务完成」；Chat 附件「文本内容」；Diff/配对/主机无匹配文案中文
  - 审计 AppBar 自动刷新标记中文
  - 协议 15/15 + 静态括号校验


## 0.1.192

- **中文与主机/对比扫尾**：
  - 主机看板：版本/运行/项目/会话/运行中芯片中文；能力标题中文；值类型中文
  - 状态页：会话/运行中芯片、桥接适配器中文
  - Diff：标题/行号/增减排序 tooltip 中文
  - 设置：刷新「关」；会话排序 ChoiceChip 全中文
  - 协议 15/15 + 静态括号校验


## 0.1.191

- **中文与体验扫尾**：
  - 权限页：筛选/规则/空态/工具标签全中文
  - 会话：排序标签与状态文案中文（模型/项目/实时/归档…）
  - 状态/主机：健康时间、Hermes 进程、Mgmt/Bridge 中文
  - 协议 15/15 + 静态括号校验


## 0.1.190

- **修 CI 编译**（APK 构建失败根因）：
  - Connect CTA 调用 `_onConnect`（误用已删 `_testAndConnect`）
  - `AppTheme` 补 `cupertino.dart`（`CupertinoPageTransitionsBuilder`）
  - Sessions 补 `CatalogUi` import
  - Workspace `onTick: _load`（勿立即调用）
  - Status 健康卡 `Card` 双 ListTile 包 `Column`
  - 协议 15/15 + 静态括号校验


## 0.1.189

- **手机可用性扫尾**：
  - Sessions 多选：仅保留删除 + 更多（导出/置顶/归档）
  - 主机看板 AppBar：刷新/自动刷新 + 更多（复制/排序/滚动）
  - 工具宫格：手机两列更高卡片（更好点）
  - 协议 15/15 + 静态括号校验


## 0.1.188

- **手机可用性续**：
  - Sessions：列表卡片化、更大行高、圆角状态图标、分组头中文、置顶/归档中文菜单
  - Connect：首连短路径（名称/主机/双令牌）+「高级选项」折叠端口/TLS；修复重复 CTA
  - 协议 15/15 + 静态括号校验


## 0.1.187

- **手机可用性**：
  - Connect AppBar：10+ 图标收敛为「导入 / 新建 / 更多」
  - Sessions AppBar：常态仅保留刷新 + 更多（主题/多选进菜单）
  - 全局 IconButton 最小 44×44；FilterChip 加大触控
  - Chat 输入区：底栏边框 +「+」收纳附件/斜杠/历史，发送键 48×48
  - 协议 15/15 + 静态括号校验


## 0.1.186

- **真正的 UI 设计升级**（Linear 风 · 现代控制台）：
  - `AppTheme` 重写：暗色原生 canvas (`#08090A`)、indigo 强调色 (`#5E6AD2`/`#7170FF`)、半透明边框、去 elevation 阴影、精确字重/字距
  - Connect：去掉旧蓝渐变 hero + 白底功能卡，改为主题感知品牌条 + pill 能力标签 + 现代状态卡 + CTA
  - HomeShell：连接条改为圆角状态胶囊（绿/琥珀指示 + mono 主机名）
  - Console 组件：空态/卡片/工具宫格改为半透明表面 + 细边框（暗色更干净）
  - Chat 欢迎态：方角品牌标 + 建议卡边框现代化；连接文案中文
  - 协议 15/15 + 静态括号校验


## 0.1.185

- UI 优化（中文 + LiveAgent 风主路径）：
  - `AppStrings` 扩展筛选/排序/Git/状态文案；全屏 FilterChip（换行/正则/大小写/自动刷新/最新在前…）中文化
  - 主机看板健康条/最近成功/自动刷新文案中文化；会话菜单 备注/重命名/删除 中文化
  - `HomeShell` 顶部连接状态条（在线指示 + 主机 + 切换连接）
  - `AppTheme`：Cupertino 页转场、圆角 Dialog/BottomSheet
  - 工具宫格：代理/对比 中文标签；Markdown 复制提示中文
  - 协议回归 15/15 + py_compile


## 0.1.184

- Phase D mock / MD 维护性：
  - mock_host：`MOCK_TERM_HANDLERS` 表驱动调度（140+ 简单命令），catalog 扩至 224 并与 help/which/type 锁步
  - 修复 help/perm 缺 return 与 `import time` 局部遮蔽导致 date 崩
  - MarkdownLite 核心路径瘦身（~2.0k → ~1.4k）；legacy HTML 拆到 `markdown_lite_legacy.dart`
  - 协议回归 15/15 + py_compile


## 0.1.183

- Phase C Chat/Terminal 体验：
  - 默认折叠工具消息（`showToolsDefault=false`），气泡内可展开/收起工具输出
  - 权限请求顶部快捷条 + 权限气泡强调按钮（允许/拒绝/全部允许）
  - Chat AppBar 收敛：导出/复制/清除/重载/审计进 overflow；ListView `cacheExtent`
  - Terminal AppBar 收敛为查找/历史/重连 + overflow；非完整 PTY 提示条
  - Chat/Terminal 中文扫尾；`AppStrings` 扩展聊天/终端文案

## 0.1.182

- Phase B Catalog 收敛：`CatalogUi` 统一 auto-refresh / copy snack / 中文标签
- 14 个 catalog/host 屏 `_armTimer` 改为 `CatalogUi.armAutoRefresh`
- Skills/MCP/Cron/Memory/Agents/Logs/Activity/Audit 查询改用 `QueryMatch`
- 全屏中文扫尾：Settings / Status / Dashboard / Pairing / Sessions / Chat / Terminal / Workspace 等用户可见文案
- 协议回归：15/15 + py_compile

## 0.1.181

- 全量代码审计与重设计文档：`docs/CODE_AUDIT_AND_REDESIGN.md`
- 共享层：`AppStrings` / `QueryMatch` / `UiHelpers` / `ConsoleWidgets`
- `SessionLocalStore` 门面统一 pins/notes/archive/recents
- `AppTheme` 升级：圆角卡片、NavigationBar、输入框、surface 层级
- `HomeShell` 底部导航：会话 · 主机 · 工具 · 设置
- `ToolsHubScreen` 工具宫格入口
- Sessions：embedded 模式、AppBar 收敛到 overflow、中文文案、本地 store 门面
- 烟测改为中文断言；设置页 tooltip 中文化


## 0.1.180

- UI: LiveAgent-style chat interface redesign
- Message bubbles: clean white cards with soft blue user messages
- Welcome screen: centered logo + greeting + 3 suggestion cards
- Input area: rounded container with Chinese placeholder
- Role icons: person/assistant/tool/system indicators

## 0.1.179

- Fix: add ConnectionController import to settings_screen


## 0.1.178

- Fix: Column bracket mismatch in chat_screen
- Fix: ConnectionController import in settings_screen


## 0.1.177

- Fix: chat_screen if-expression syntax (Column wrapper)
- Fix: add _jumpToTop method
- Fix: add _fmtTime helper function


## 0.1.176

- Fix: MarkdownLite positional args in workspace_screen
- Fix: add missing _codeLangFor method
- Fix: remove softWrap from SelectableText in terminal_screen


## 0.1.175

- Fix: TranscriptMessage.text -> .content, buttons -> meta[buttons]
- Fix: permissions_screen + chat_screen permission badge


## 0.1.174

- Fix: enable core library desugaring for flutter_local_notifications
- Fix: _wrapLines -> wrapLines parameter in _ConnectionStatusBanner
- Fix: NDK version 27->28 (required by jni plugin)
- Fix: minSdk 21 + multiDexEnabled for desugaring


## 0.1.173

- Fix: Dart compilation errors (dot-shorthand, tuple indexing, session.name)
- Fix: Upgrade AGP 8.7.3→8.9.1, Kotlin 2.1.0→2.2.20, Gradle 8.12→8.14
- Fix: audit_screen cascade sort, connection_fingerprint record destructure
- Fix: chat_controller session.name→session.displayTitle


## 0.1.172

- Offline queue: cache messages when disconnected, auto-flush on reconnect
- OfflineQueue service with disk persistence
- Queue badge in chat AppBar showing pending count
- Queue dialog with clear option
- All 8 competitive gaps resolved


## 0.1.171

- Responsive layout: breakpoints for mobile/tablet/desktop
- ResponsiveMasterDetail widget for master-detail layouts
- Responsive padding and grid columns for larger screens
- ResponsiveLayout helper class with screen detection


## 0.1.170

- Agent event notifications: permission request, task error, disconnect
- Permission request notification when agent needs approval
- Task error notification on agent failure
- Bridge disconnect notification with reconnect hint
- NotificationService integration in ChatController


## 0.1.169

- Git actions: commit/push/pull from workspace screen
- Git commit dialog with message input
- Git push/pull with success/failure feedback
- Mock git endpoints: POST /workspace/git/commit, /push, /pull
- MgmtClient: gitCommit(), gitPush(), gitPull() methods


## 0.1.168

- Permissions screen: pending/approved/denied permission management
- Auto-approve rules: configure tools to skip permission prompts
- Permission badge on chat AppBar: shows pending count
- Mock /perm command: sends permission request card with Allow/Deny buttons
- Competitive gap analysis: 8 features identified vs CodeAgent Mobile/tlbx/codex-tg


## 0.1.167

- Hermes adapter detection: show Mock vs Real Hermes in settings
- ConnectionController.adapterType / isRealHermes getters
- Settings dynamically displays connected host type
- App compatible with both mock and real Hermes hosts


## 0.1.166

- Real PTY support: HUAN_REAL_PTY=1 enables real shell with PTY
- RealPtyManager: spawn/resize/cleanup real shell processes
- Terminal resize forwarded to real PTY via ioctl
- Falls back to mock when HUAN_REAL_PTY not set


## 0.1.165

- QR code generation on pairing screen (share connection via QR)
- QR code scanner on connect screen (scan to import pairing URI)
- Added qr_flutter + mobile_scanner packages
- Updated all "future P4" references to live features


## 0.1.164

- System notifications: flutter_local_notifications + Android POST_NOTIFICATIONS permission
- File picker: real file/image picking from device storage, gallery, or camera
- Image picker: camera and gallery integration for image attachments
- Notification service: task completion + error alerts with channel support
- File picker service: unified file/image/video picking interface


## 0.1.163

- Refactor: remove 25 duplicate elif handler blocks (-73 lines)
- Fix: resolve 8 Dart analyzer warnings (unnecessary type checks/casts/null assertions)
- Fix: remove unused _copyStatus from _StatChip
- Fix: dedup known/builtins sets (193 unique entries)


## 0.1.162

- Fix: mock df/free/ps/uptime handlers (were in help but missing)


## 0.1.161

- Newest FilterChips on activity/logs/memory screens


## 0.1.160

- Mock ip/netstat/traceroute (+ help/which/type lockstep)
- Handler cleanup (subagent refactored to compact form)


## 0.1.159

- Mock 22 commands: shell/archive/network + editors/system/admin
- Mock bash/sh/exit/logout/source/set (+ help/which/type lockstep)
- Mock tar/gzip/gunzip/zip/unzip (+ help/which/type lockstep)
- Mock curl/wget/ssh/scp/rsync/ping (+ help/which/type lockstep)
- Mock man/info/vi/nano/screen/tmux (+ help/which/type lockstep)
- Mock mount/umount/dd/service/systemctl/lsblk/fdisk (+ help/which/type lockstep)
- Mock at/cron/crontab/useradd/userdel/usermod/groupadd/groupdel/mail (+ help/which/type lockstep)

## 0.1.158

- Mock cp/mv/rm/chmod/chown/chgrp (+ help/which/type lockstep)
- Mock less/more/awk/sed (+ help/which/type lockstep)
- Mock kill/jobs/bg/fg (+ help/which/type lockstep)

## 0.1.157

- Auto refresh FilterChips on skills/status/workspace screens (completes all screens)
- MarkdownLite `<footer>` + `<hgroup>`
- Mock true/false/unset (+ help/which/type lockstep)

## 0.1.156

- Auto refresh FilterChips on mcp/memory/sessions screens
- MarkdownLite `<section>` + `<article>` + `<header>`
- Mock ulimit/finger/nologin (+ help/which/type lockstep)

## 0.1.155

- Auto refresh FilterChips on diff/host_dashboard/logs screens
- MarkdownLite `<main>` + `<aside>` + `<nav>`
- Mock lastb/faillog/chage (+ help/which/type lockstep)

## 0.1.154

- Auto refresh FilterChips on activity/agents/audit/cron screens
- MarkdownLite `<figcaption>` + `<map>`
- Mock history/alias/unalias (+ help/which/type lockstep)

## 0.1.153

- Terminal view Find FilterChip
- MarkdownLite `<progress>` + `<figure>`
- Mock chsh/passwd/lastlog (+ help/which/type lockstep; demo-only)

## 0.1.152

- Diff view Line# FilterChip
- MarkdownLite `<slot>` + `<meter>`
- Mock su/sudo/chfn (+ help/which/type lockstep; demo-only auth failure)

## 0.1.151

- Terminal view FilterChips (regex / case; wrap already present)
- MarkdownLite `<dialog>` + `<template>`
- Mock write/wall/newgrp (+ help/which/type lockstep)

## 0.1.150

- Diff view FilterChips (wrap / regex / case)
- MarkdownLite `<iframe>` + `<portal>`
- Mock id/login/mesg (+ help/which/type lockstep)

## 0.1.149

- Chat view FilterChips (wrap / regex / case)
- MarkdownLite `<math>` + `<area>`
- Mock stty/uname/hostname (+ help/which/type lockstep)

## 0.1.148

- Skills view FilterChips (wrap / regex / case)
- MarkdownLite `<canvas>` + `<svg>`
- Mock toe/reset/resize (+ help/which/type lockstep)

## 0.1.147

- Agents view FilterChips (wrap / regex / case)
- MarkdownLite `<audio>` + `<picture>`
- Mock script/scriptreplay/infocmp (+ help/which/type lockstep)

## 0.1.146

- Cron view FilterChips (wrap / regex / case)
- MarkdownLite `<track>` + `<video>`
- Mock tput/tset/tabs (+ help/which/type lockstep)

## 0.1.145

- Workspace view FilterChips (wrap / regex / case)
- MarkdownLite `<object>` + `<param>`
- Mock base64/md5sum/dircolors (+ help/which/type lockstep)

## 0.1.144

- MCP view FilterChips (wrap / regex / case)
- MarkdownLite `<noframes>` + `<embed>`
- Mock base32/sha224sum/sha384sum (+ help/which/type lockstep)

## 0.1.143

- Host dashboard FilterChips (wrap / regex / case)
- MarkdownLite `<applet>` + `<noembed>`
- Mock diff3/pr/sha512sum (+ help/which/type lockstep)

## 0.1.142

- Activity view FilterChips (wrap / regex / case)
- MarkdownLite `<frame>` + `<frameset>`
- Mock diff/patch/sdiff (+ help/which/type lockstep)

## 0.1.141

- Sessions view FilterChips (wrap / regex / case)
- MarkdownLite `<bgsound>` + `<multicol>`
- Mock getopt/strings/csplit (+ help/which/type lockstep)

## 0.1.140

- Logs view FilterChips (wrap / regex / case)
- MarkdownLite `<nextid>` + `<keygen>`
- Mock mkdir/rmdir/mkfifo (+ help/which/type lockstep)

## 0.1.139

- Memory view FilterChips (wrap / regex / case)
- MarkdownLite `<isindex>` + `<spacer>`
- Mock printf/realpath/touch (+ help/which/type lockstep)

## 0.1.138

- Status view FilterChips (wrap / regex / case)
- MarkdownLite `<dir>` + `<menu>`
- Mock ldconfig/uuidgen/seq (+ help/which/type lockstep)

## 0.1.137

- Chat search/tools FilterChips (regex / case / tools)
- MarkdownLite `<plaintext>` + `<basefont>`
- Mock capsh/runcon/ldd (+ help/which/type lockstep)

## 0.1.136

- Audit view FilterChips (wrap / regex / case / newest)
- MarkdownLite `<xmp>` + `<listing>`
- Mock unshare/nsenter/setpriv (+ help/which/type lockstep)

## 0.1.135

- Connect query FilterChips (wrap / regex / case)
- MarkdownLite `<blink>` + `<marquee>`
- Mock taskset/prlimit/chroot (+ help/which/type lockstep)

## 0.1.134

- Settings pref FilterChips (wrap / regex / case)
- MarkdownLite `<acronym>` + `<nobr>`
- Mock stdbuf/flock/ionice (+ help/which/type lockstep)

## 0.1.133

- Pairing view FilterChips (wrap / regex / case / sort / auto)
- MarkdownLite `<wbr>` + `<rp>`
- Mock nice/nohup/watch (+ help/which/type lockstep)

## 0.1.132

- Terminal view FilterChips (wrap / newest / timestamps)
- MarkdownLite `<font>` + `<center>`
- Mock install/shred/timeout (+ help/which/type lockstep)

## 0.1.131

- Chat permission role filter chip
- MarkdownLite `<ruby>` + `<rt>`
- Mock link/ln/truncate (+ help/which/type lockstep)

## 0.1.130

- Audit action chips expand (host/git/settings/terminal/other)
- MarkdownLite `<bdi>` + `<bdo>`
- Mock pathchk/mktemp/sync (+ help/which/type lockstep)

## 0.1.129

- MCP kind filter chips
- MarkdownLite `<time>` + `<data>`
- Mock dir/vdir/tsort (+ help/which/type lockstep)

## 0.1.128

- Logs logger filter chips
- MarkdownLite `<br>` + `<strike>`
- Mock unexpand/tac/namei (+ help/which/type lockstep)

## 0.1.127

- Skills tag filter chips
- MarkdownLite HTML `<mark>`
- Mock cksum/sum/expand (+ help/which/type lockstep)

## 0.1.126

- Diff path-prefix filter chips
- MarkdownLite `<big>` + `<tt>`
- Mock locale/umask/readlink (+ help/which/type lockstep)

## 0.1.125

- Workspace extension filter chips
- MarkdownLite `<code>` + `<i>`
- Mock join/split/getent (+ help/which/type lockstep)

## 0.1.124

- Cron last_status filter chips
- MarkdownLite `<strong>` + `<b>`
- Mock paste/column/comm (+ help/which/type lockstep)

## 0.1.123

- Host dashboard value-type filter chips
- MarkdownLite `<dfn>` + `<em>`
- Mock lscpu/fmt/shuf (+ help/which/type lockstep)

## 0.1.122

- Agents platform filter chips
- MarkdownLite `<var>` + `<samp>`
- Mock w/last/cal (+ help/which/type lockstep)

## 0.1.121

- Sessions platform filter chips
- MarkdownLite `<cite>` + `<q>`
- Mock users/tty/who (+ help/which/type lockstep)

## 0.1.120

- Status value-type filter chips
- MarkdownLite `***` bold-italic + `<small>`
- Mock printenv/logname/groups (+ help/which/type lockstep)

## 0.1.119

- Agents model filter chips
- MarkdownLite `<ins>` + `<s>`
- Mock arch/getconf/numfmt (+ help/which/type lockstep)

## 0.1.118

- Agents adapter filter chips
- MarkdownLite h6 + `<del>`
- Mock nproc/factor/bc (+ help/which/type lockstep)

## 0.1.117

- Activity source filter chips + diversified seed sources
- MarkdownLite h5 + `<u>` underline
- Mock od/expr/test (+ type/which/help lockstep)

## 0.1.116

- Sessions agent_type filter chips
- Cron kind filter chips
- MarkdownLite h4 + `<abbr title>`
- Mock yes/tee/xargs

## 0.1.115

- Memory tag filter chips
- MarkdownLite footnotes `[^id]` / `[^id]:`
- Mock tr/rev/cmp terminal builtins

## 0.1.114

- Logs source filter chips + API `source` query
- MarkdownLite `<sup>` / `<sub>`
- Mock fold/hexdump/xxd/jq; richer log seeds

## 0.1.113

- Skills category filter chips
- MarkdownLite `||spoiler||` (blacked-out text)
- Mock md5sum/sha1sum/sha256sum, nl, cut

## 0.1.112

- MCP enabled filter chips + catalog enabled flags
- MarkdownLite `<details>/<summary>` ExpansionTile
- Mock base64/file/uniq/type terminal builtins

## 0.1.111

- Activity level filter chips (info/warn/error/debug)
- Agents subtitle shows adapter/process; hermes agent mock fields
- Mock date +FMT, sort/export/env session vars; head/tail -n

## 0.1.110

- Status screen Bridge adapters list + copy summary
- MarkdownLite `<kbd>` keys
- Mock terminal grep/find/seq over workspace tree

## 0.1.109

- Chat in-app SnackBar on silent Reconnected
- Workspace source files preview via MarkdownLite fenced highlight
- Mock sleep/touch/history + hermes project caps deepen

## 0.1.108

- MarkdownLite bare URL autolink (console-safe)
- Diff file chips status-colored avatars
- Workspace .md preview via MarkdownLite
- Mock terminal true/false/printf + help

## 0.1.107

- MarkdownLite `==mark==` highlight
- Mock terminal basename/dirname/realpath/stat/du + which/help

## 0.1.106

- MarkdownLite GitHub-style callouts (`> [!NOTE]` / TIP / WARN / IMPORTANT)
- Mock terminal tree/df/free/ps/uptime
- Audit action-prefix filter chips (bridge/session/chat/permission)

## 0.1.105

- MarkdownLite image `![alt](url)` console-safe alt chip (no network)
- Mock terminal which/head/tail/wc + cat from workspace tree
- Host dashboard hermes adapter chip + copy metadata

## 0.1.104

- Mock terminal cd/mkdir (readonly tree) + help; workdir-aware ls
- Terminal input hint shows local workdir track
- Activity list level/source + seed levels; filter includes them

## 0.1.103

- Mock workspace hermes/ + docs/protocol; git status + diffs
- Terminal ls dynamic from workspace tree
- Logs show source/logger; code block header line count

## 0.1.102

- MarkdownLite ordered lists + multi-line blockquotes
- Attach dialog presets (note/md/json/log) + mime by extension
- Mock hermes cron jobs, host log seed, terminal clear/reset
- Cron UI shows project/tags when present

## 0.1.101

- Settings terminal font scale (device-local) wired into Terminal screen
- Mock memory hermes entries + tags in Memory UI; MCP hermes-memory/skills catalog
- Mock agents claude-code/codex capabilities + MCP kind/note fields

## 0.1.100

- MarkdownLite strikethrough ~~text~~ (P4-5)
- Agents subtitle note + capabilities; Status hermes adapter chip (P4-3)
- In-app permission SnackBar (not system notifications) (P4-4)
- Mock status hermes block + activity seed events (P4-3/P4-4 surface)

## 0.1.99

- MarkdownLite task lists + richer link display (P4-5)
- Terminal AppLifecycle resume reconnect + Reconnect action (P4-4)
- Pairing “Copy paste card” for Connect import (P4-2)
- Mock skills category/version/tags + Skills UI meta; hermes reply task/link demo (P4-3)

## 0.1.98

- MarkdownLite GFM tables + horizontal rules (P4-5)
- Attach InputChips with per-item remove (P4-5 attach UX)
- Silent reconnect success banner clears after 2s (P4-4)
- Mock agents hermes fields + term hostname/id/cat; hermes reply demo table (P4-1/P4-3)

## 0.1.97

- Auto-reconnect prefs + configurable max attempts (P4-4)
- MarkdownLite code line-number gutter (P4-5)
- Connect clipboard prefill / paste for pairing URI (P4-2 path without camera)
- Mock Hermes memory.search hits + tool_result fix; terminal uname/date/env (P4-1/P4-3 mock)

## 0.1.96

- MarkdownLite lightweight fenced-code token tint (P4-5 partial)
- Chat foreground resume reconnect via AppLifecycle (P4-4 partial)
- Terminal layout-driven cols/rows + Mock stty size (P4-1 protocol step)

## 0.1.95

- Sessions note and archived sort modes
- Connect deviceId sort
- Workspace children-count sort

## 0.1.94

- Sessions last-message and pinned sort modes
- Connect platform and profile id sort

## 0.1.93

- Workspace status sort
- Diff basename sort
- Agents version sort
- Activity priority sort

## 0.1.92

- Sessions sort by live
- MCP explicit name sort
- Status / Host Dashboard explicit key sort

## 0.1.91

- Agents capabilities count sort
- Sessions sort by mode / workdir / running

## 0.1.90

- Workspace dirty / branch sort
- Cron last_run sort
- Sessions sort by platform / agent

## 0.1.89

- Memory explicit time/ts sort
- Activity explicit time/ts sort
- Audit explicit time/ts sort
- Cron description sort

## 0.1.88

- Cron explicit name sort
- MCP kind sort
- Logs time (ts) sort
- Skills explicit name sort

## 0.1.87

- MCP command sort
- Activity channel sort
- Agents note sort
- Workspace explicit name sort

## 0.1.86

- Status / Host value-type sort
- Diff explicit path sort
- Agents cwd sort

## 0.1.85

- Agents provider + sessions_count sort
- MCP description sort
- Connect TLS sort
- Activity type sort

## 0.1.84

- Skills enabled sort
- Memory path sort
- Logs id sort
- Connect bridgePort sort

## 0.1.83

- MCP transport + id sort
- Agents id sort
- Cron enabled sort
- Activity level sort

## 0.1.82

- Memory id sort
- Agents project sort
- Workspace type sort
- Logs source sort

## 0.1.81

- Workspace path sort
- Skills path sort
- Cron id sort
- Activity id sort

## 0.1.80

- Status regex filter (long-press)
- Host Dashboard regex filter (long-press)
- Connect profiles regex filter (long-press)
- Diff path filter regex (long-press)

## 0.1.79

- Skills regex filter (long-press)
- Sessions regex search (long-press)
- Workspace regex filter (long-press)
- Pairing payload regex filter (long-press)

## 0.1.78

- MCP regex filter (long-press)
- Cron regex filter (long-press)
- Agents regex filter (long-press)
- Memory regex search (long-press)

## 0.1.77

- Connect profile case-sensitive filter
- Diff find case + regex (long-press)
- Audit regex filter (long-press)
- Activity regex filter (long-press)

## 0.1.76

- Sessions case-sensitive search
- Settings regex preference filter (long-press)
- Logs regex filter (long-press)
- Sessions sort by session key

## 0.1.75

- Status/Host case-sensitive capability & key filters
- Connect profile sort by note
- Agents sort by platform

## 0.1.74

- Agents case-sensitive filter
- Memory case-sensitive search
- Connect profile sort by port
- Diff sort files by deletions

## 0.1.73

- Audit case-sensitive filter
- Logs case-sensitive filter
- Workspace case-sensitive filter
- Skills case-sensitive filter

## 0.1.72

- MCP case-sensitive filter
- Activity case-sensitive filter
- Cron case-sensitive filter
- Memory sort by scope

## 0.1.71

- Pairing: sort payload lines A↔Z
- Agents: sort by status
- Skills: sort by tags + search tags
- Diff: sort files by additions

## 0.1.70

- Logs: sort by logger/source
- Memory: relative timestamps toggle
- Sessions: sort by model
- Settings: case-sensitive pref filter

## 0.1.69

- Audit: relative timestamps toggle
- Activity: relative timestamps toggle
- Chat: regex transcript search (long-press)
- Cron: sort by next_run

## 0.1.68

- Memory: sort by confidence/score
- Activity: sort by source/origin
- MCP: transport filter chips
- Diff: sort files by status

## 0.1.67

- Status / Host: relative timestamps for status values
- Workspace: hide empty directories chip
- Terminal: regex find (long-press toggle)

## 0.1.66

- Sessions: filter sessions that have local notes
- Skills: sort by id/path
- Pairing: case-sensitive payload line filter
- Connect: TLS / plain profile chips

## 0.1.65

- MCP: sort by endpoint/url/command
- Cron: sort by last_status
- Diff: case-sensitive path filter
- Agents: sort by model/provider

## 0.1.64

- Activity: sort by session key
- Audit: sort by detail
- Memory: sort by content
- Chat: case-sensitive transcript search

## 0.1.63

- Workspace: sort by mtime (name → size → mtime)
- Connect: profiles sort by host / updatedAt
- Agents: status FilterChips from Host data
- Skills: sort by description

## 0.1.62

- MCP: sort by tool count
- Status / Host Dashboard: sort keys by value
- Terminal: case-sensitive find toggle
- Logs: relative timestamps toggle

## 0.1.61

- Settings: filter preference tiles by text
- Workspace: sort by size vs name (dirs first)
- Cron: sort cycle name → schedule → kind
- Chat: role filter chips (user/assistant/system/tool)

## 0.1.60

- Skills: sort by source vs name
- Agents: sort by type vs name
- Memory: sort cycle time → title → type
- Activity: sort cycle time → kind → summary

## 0.1.59

- Logs: sort cycle time → message → level
- Audit: sort cycle time → action → level
- Cron: sort by schedule vs name
- MCP: sort by status vs name

## 0.1.58

- Host Dashboard: text filter for capability chips
- Diff: status chips filter for changed files
- Connect: A→Z / Z→A sort for profile chips
- Pairing: filter host payload lines

## 0.1.57

- Terminal: newest/oldest line order toggle
- Settings: wrap/clamp long preference subtitles
- Sessions: reverse sort direction (A→Z/Z→A, newest/oldest)
- Status: filter capability chips

## 0.1.56

- Audit: sort by action A→Z / Z→A
- Logs: sort by message A→Z / Z→A
- Connect: jump to top / end
- Settings: jump to top / end (Stateful)

## 0.1.55

- Status: filter raw keys / values
- Host Dashboard: filter raw /status keys
- Connect: wrap / clamp health text and profile labels
- Activity: sort by kind A→Z / Z→A (with time fallback)

## 0.1.54

- Status: sort keys A→Z / Z→A
- Host Dashboard: sort keys A→Z / Z→A
- Memory: sort by title A→Z / Z→A (toggle with time order)
- Chat: clamp / expand long messages

## 0.1.53

- Pairing: wrap/clamp payload and host line
- Host Dashboard: wrap/clamp status values
- Sessions: wrap/clamp title and subtitle
- Diff: files A→Z / Z→A sort

## 0.1.52

- Skills: wrap/clamp list details
- MCP: wrap/clamp list details
- Cron: wrap/clamp list details
- Workspace: wrap/clamp path/entry details

## 0.1.51

- Host Dashboard: pause/resume auto-refresh
- Status: wrap/clamp raw status values
- Connect: copy profiles CSV (no tokens)
- Agents: wrap/clamp list details

## 0.1.50

- Pairing: copy public CSV (no tokens)
- Diff: auto-refresh toggle (dashboard interval)
- Settings: copy about / version text
- Terminal: copy buffer as CSV lines

## 0.1.49

- Activity: wrap / clamp event titles
- Memory: wrap / clamp content preview
- Workspace: copy listing CSV
- Sessions: copy visible meta CSV (no tokens)

## 0.1.48

- Sessions: auto-refresh toggle (dashboard interval)
- Logs: newest / oldest sort
- Diff: copy filtered files CSV
- Chat: copy all visible messages (local transcript)

## 0.1.47

- Audit: auto-refresh toggle (dashboard interval; local re-render)
- Status: jump to top / end
- Pairing: jump to top / end
- Host Dashboard: jump to top / end

## 0.1.46

- Pairing: auto-refresh toggle (dashboard interval)
- Connect: copy fingerprint hex (no tokens)
- Sessions: jump to top / end
- Host Dashboard: copy status CSV

## 0.1.45

- Skills: auto-refresh toggle (dashboard interval)
- Cron: auto-refresh toggle (dashboard interval)
- Memory: auto-refresh toggle (dashboard interval)
- Workspace: auto-refresh toggle (dashboard interval)

## 0.1.44

- Activity: jump to top / end
- Audit: jump to top / end
- Agents: auto-refresh toggle (dashboard interval)
- MCP: auto-refresh toggle (dashboard interval)

## 0.1.43

- Agents: jump to top / end
- MCP: jump to top / end
- Skills: jump to top / end
- Cron: jump to top / end

## 0.1.42

- Activity: auto-refresh toggle (dashboard interval)
- Workspace: jump to top / end
- Status: copy CSV (redacted host meta)
- Memory: jump to top / end

## 0.1.41

- MCP: A→Z / Z→A name sort
- Cron: A→Z / Z→A name sort
- Logs: auto-refresh toggle (dashboard interval)
- Audit: wrap / clamp detail lines

## 0.1.40

- Agents: A→Z / Z→A name sort
- Skills: A→Z / Z→A name sort
- Diff: jump to top / end
- Pairing: copy public JSON (no tokens)

## 0.1.39

- Terminal: jump to top / end
- Memory: newest/oldest sort toggle
- Settings: reset console prefs to defaults (no tokens)
- Host Dashboard: copy capabilities list

## 0.1.38

- Activity: newest/oldest sort toggle
- Status: auto-refresh (dashboard interval) + pause
- Workspace: All/Dirs/Files type FilterChips
- Logs: jump to top / end

## 0.1.37

- Terminal: local display timestamps toggle
- Status: Copy JSON (tokens redacted)
- Connect: copy public profiles list (no tokens)
- Diff: +adds/-dels stats in title

## 0.1.36

- Memory: Copy CSV of filtered entries
- Diff: wrap / horizontal scroll toggle
- Workspace: copy git summary (branch + changed files)
- Host Dashboard: capability FilterChips + count title

## 0.1.35

- Agents: Copy CSV of agents/projects/platforms catalog
- MCP: Copy CSV of filtered servers
- Skills: Copy CSV of filtered skills
- Cron: Copy CSV of filtered schedules

## 0.1.34

- Activity: Copy CSV of filtered events
- Memory: type FilterChips + filtered/total title
- Settings: copy local prefs summary (no tokens)
- Status: last connect test latency tile + summary field

## 0.1.33

- Cron: filtered/total title counts
- Host logs: Copy CSV of filtered lines
- Workspace: dirs-first name sort toggle + filtered/total title
- Audit: newest/oldest sort toggle; Copy all tooltip

## 0.1.32

- Skills: source FilterChips + filtered/total title counts
- Diff: local find-in-diff (display filter; copy still full diff)
- Host Dashboard: auto-refresh badge + last-ok time chips
- Pairing: AppBar copy public summary / public URI (no tokens)

## 0.1.31

- Activity: kind FilterChips + filtered/total title counts
- Agents: section chips (agents / platforms / projects)
- MCP: status FilterChips + filtered/total title counts
- Terminal: local find-in-buffer (client-only; copy still full buffer)

## 0.1.30

- Host logs: wrap toggle + title counts (filtered/total)
- Memory: scope FilterChips + clearer search chrome
- Workspace: copy directory listing + entry count in title
- Settings/Chat: chat body font scale (0.9–1.3×, device-local)

## 0.1.29

- Audit: title counts + CSV export of filtered rows
- Pairing: pull-to-refresh
- Diff: optional line numbers
- Connect: last Test & connect latency (ms) on phase banner

## 0.1.28

- Status + Host Dashboard pull-to-refresh
- Agents / Skills / MCP: Copy all + title counts
- Diff: copy path; Terminal: clear local buffer
- Connect: copy public summary (no tokens)
- Settings: keep-screen-on preference + monospace chat bodies

## 0.1.27

- Memory: live client-side refine filter + title count; Copy all follows filter
- Cron / Activity: Copy all filtered jobs/events + title counts
- Chat: subtitle shows message count and tools-hidden hint
- Pairing: larger fingerprint (13×13), hex tag + copy, verify checklist
- Workspace: path breadcrumb chips (navigate ancestors)

## [0.1.26] - 2026-07-17

### Added
- Host logs local message/level filter (client-side)
- Terminal wrap toggle with horizontal scroll when unwrap
- Sessions menu: Copy ids (title/id/session_key/project)
- Settings haptic feedback toggle; light buzz on send/pin

## [0.1.25] - 2026-07-17

### Added
- Chat: clear local transcript view (Host history untouched; Reload to refetch)
- Sessions: search debounce (220ms)
- Connect: connection status banner (ready / degraded / testing / error / idle)
- Status: last health probe card + copy health error; summary includes health fields

## [0.1.24] - 2026-07-17

### Added
- Pull-to-refresh on Agents, Audit, Workspace, Diff
- Host Dashboard copy status summary (no token)
- Chat jump-to-top FAB alongside jump-to-latest
- Terminal local font scale (A− / A+)

## [0.1.23] - 2026-07-17

### Added
- Memory: copy entry / copy all export + pull-to-refresh
- Workspace: copy path / file content; long-press entry copies path
- Pull-to-refresh on Logs, Activity, Cron, Skills, MCP
- Chat local message timestamps (HH:mm:ss on bubbles)
- Settings: app version + privacy notes

## [0.1.22] - 2026-07-17

### Added
- Agents catalog filter/copy; fixed agent title/subtitle helpers
- Diff viewer: filter changed files + copy full diff
- Status landing: health strip, snapshot chips, copy summary (no token), open sessions/dashboard
- Chat bubbles honor Compact lists (tighter margin/padding)

## [0.1.21] - 2026-07-17

### Added
- Skills / MCP local filter + copy entry
- Cron text filter + enabled/disabled chips + long-press copy
- Workspace directory entry filter (clears on navigate)
- Host Dashboard health strip (healthy / degraded / error) with Check

## [0.1.20] - 2026-07-17

### Added
- Chat composer draft autosave per session_key (device local; cleared on send)
- Sessions Group-by-project headers + Group filter chip
- Terminal local command history (↑/↓, history sheet; device only)
- Host logs: stronger level color strips/badges, fatal/critical colors, Copy all

## [0.1.19] - 2026-07-17

### Added
- Prompt history panel: filter, copy, append/replace into composer
- Sessions swipe shortcuts (pin / archive) + overflow actions menu
- Project capability badges on session tiles; Host dashboard cap icons
- Chat quote-reply: long-press message → Quote banner → send as blockquote

## [0.1.18] - 2026-07-17

### Added
- Chat/Terminal connection status lights (connecting/live/offline)
- Device-local session recents + Sort: Recent (pins still first)
- Host activity filter + tap-to-open session (or copy ref)
- Audit log Copy JSON export (redacted entries)

## [0.1.17] - 2026-07-17

### Added
- Host health heartbeat: 30s GET /status probe while connected + Sessions health strip + manual Check
- Richer Sessions empty states (first-run guide + filter reset)
- Session metadata export to clipboard (tile / visible list menu / multi-select)
- Terminal "Copy all" for local buffer (tokens still never logged)

## [0.1.16] - 2026-07-17

### Added
- Session list sort modes: updated / title / project / created (Settings + list chip; pins still first)
- In-session host profile switcher (test-and-connect another saved profile)
- Chat search hit navigation (prev/next, N/M counter, active hit border)
- High-contrast appearance toggle in Settings (stronger outlines/surfaces)
- SessionInfo.createdAt parsing for created-time sort

## [0.1.15] - 2026-07-17

### Added
- Connection share: public pairing URI / summary (no tokens) + visual fingerprint on Pairing screen
- Sessions multi-select: bulk pin / archive-or-unarchive / delete; long-press enters selection
- Chat tool-message toggle (honors Settings default showTools)
- Chat jump-to-bottom FAB; auto-scroll only while stick-to-bottom

### Notes
- Fingerprint is human verification only — camera QR scan remains P4

## [0.1.14] - 2026-07-17

### Added
- Settings screen: text scale, compact lists, dashboard auto-refresh interval, tools default
- Session local archive (hide from default list; Archived filter chip)
- Audit log search + level chips + copy visible / long-press copy entry
- Host dashboard auto-refresh driven by settings (default 15s)

## [0.1.13] - 2026-07-17

### Added
- Session rename via `PATCH /sessions/{id}` (title/name) + UI
- Message long-press copy to clipboard
- Theme toggle (system / light / dark, device local)
- Host logs readonly screen (`GET /logs`, capability `logs_readonly`)
- Mock Host log ring buffer + rename activity/log events

## [0.1.12] - 2026-07-17

### Added
- Agents catalog screen (`GET /agents` + projects summary)
- Device-local session notes (long-press / note icon; never uploaded)
- Session list filter chips: All / Pinned / Running
- Chat slash-command palette (fills input)
- MarkdownLite code fences: language label + copy button
- Mock `/agents` returns structured agent objects

## [0.1.11] - 2026-07-17

### Added
- Bridge reconnect UX: countdown hint, status chip tap, manual Reconnect
- In-chat transcript search with amber highlight on hits
- Export transcript to clipboard (Markdown + plain)
- Attachment demo chips with text preview sheet
- Host activity feed (`GET /activity`) + Activity screen + menu/dashboard links

### Protocol
- management-subset: `/activity?limit=`
- status capability: `activity_readonly`
- Mock activity ring buffer on host.start / session.create / chat.message

## [0.1.10] - 2026-07-17

### Added
- MarkdownLite chat bubbles (headings/lists/code/bold; no extra pub package)
- Host memory browser (`GET /memory`) + Cron schedules (`GET /cron`) readonly
- Git diff viewer (`GET /workspace/diff`) with green/red unified coloring
- Session pin/favorite (device-local SharedPreferences)
- Dashboard + Sessions menu shortcuts for memory/cron/diff
- Mock markdown-rich agent replies for UI verification

### Protocol
- management-subset: `/memory`, `/cron`, `/workspace/diff`
- status capabilities: `memory_readonly`, `cron_readonly`, `diff_readonly`

## [0.1.9] - 2026-07-17

### Added
- Host status dashboard (refreshable `/status`, capability chips, shortcuts)
- Readonly workspace browser (`GET /workspace`, `/workspace/git`) + Mock tree
- Chat local prompt history + favorites (device SharedPreferences only)
- Terminal quick-action chips: help/pwd/ls/whoami/y/n/^C/clear
- Status payload: `sessions_count`, `active_runs`, `capabilities[]`

### Notes
- Inspired by common remote-console UX patterns; **in-repo only**, no third-party runtime
- Workspace is readonly demo — Host remains source of truth

## [0.1.8] - 2026-07-17

### Added
- Lightweight Bridge terminal channel (`terminal_input` / `terminal_out`) + App Terminal screen
- MCP readonly catalog (`GET /mcp`) + MCP screen
- Connect: import `huanhermes://connect?...` pairing URI (tokens optional; never wipe existing)
- Sessions local search filter
- Protocol docs for terminal + MCP endpoints

### Notes
- Terminal is protocol demo / Mock echo — not a full remote PTY
- Product remains HuanHermes-owned Host protocol only


## [0.1.7] - 2026-07-17

### Changed
- Product framing: HuanHermes **owns** Bridge/Mgmt protocol; Mock/self-host are first-class
- Docs/comments no longer present third-party hosts as install/runtime dependency
- Session paths described as flat vs project-scoped (not external product dialects)

### Notes
- Behavior unchanged: dual-path Mgmt + Mock still work; only wording/ownership clarified


## [0.1.6] - 2026-07-17

### Added
- Hermes Mock session flavor (memory.search tool, hermes project)
- Capability-gated chat toolbar (mode/model/dir/stop/tools)
- Attachments protocol path + in-app attach demo
- Skills readonly screen + GET /skills on Mock
- Pairing screen + GET /pairing (token-free URI)
- Release checklist + self-host compatibility guide

### Notes
- Live Host / channels untouched; App remains console-only


## [0.1.5] - 2026-07-17

### Added
- ADR-002 Hermes adapter (App stays console; Host-side hermes agent_type + capabilities)
- Multi-server connection profiles (secure per-profile tokens, migrate v1 → v2)
- Connect UI: profile chips, new/delete profile, TLS plaintext warning
- `Security.redactText` helpers; Mock project `capabilities` fields

### Notes
- Does not modify any live Host / channel config
- Real Hermes process still Host-side (P2-2+)


## [0.1.4] - 2026-07-17

### Added
- Management dual-dialect client: flat `/sessions` (Mock) + project-scoped `/projects/{}/sessions` (project-scoped)
- Mock Host mirrors both path shapes + `/agents`, project session detail
- `docs/guides/connect-real-host.md` — user connects App to their Host without editing Host channels
- Bridge handling for `preview_start` / `card` / `update_message` (protocol reference)

### Notes
- External projects are design references only; this repo does not modify production Host configs
- App still does not run coding agent loops locally


## [0.1.3] - 2026-07-17

### Added
- Console controls: mode / model / dir / stop toolbar
- Bridge `cancel` + Mock cancellable streaming runs (`run_done`, thinking, tool_*)
- Session transcript reload via `GET /api/v1/sessions/{id}`
- Auto-reconnect with backoff; local redacted audit log screen
- Empty states for sessions/chat; running indicator
- `docs/roadmap-console-parity.md` capability matrix

### Notes
- P1-2 real Host connect path via App tokens + dual-path client
- App remains a remote console — agent loop stays on server


## [0.1.2] - 2026-07-17

### Added
- P0-8 Sessions screen: list / create / delete via Management API
- P0-8 Chat screen: Bridge WS connect, streaming transcript, send message
- P0-9 Flutter `TranscriptReducer` (stream collapse + permission events)
- P0-10 Permission buttons UI (`allow` / `deny` / `allow_all` → `card_action`)
- Dart `BridgeClient` + expanded `MgmtClient` (sessions CRUD)
- Unit tests for transcript reducer and session create


## [0.1.1] - 2026-07-17

### Added
- Flutter Android app scaffold under `apps/mobile` (`com.huanmeng.huanhermes`)
- P0-7 Connect screen: host/ports/TLS/tokens
- Secure token storage (`flutter_secure_storage`) + public prefs (`shared_preferences`)
- Management client + typed errors; connection test via `GET /api/v1/status`
- Unit tests for connection config / mgmt client / controller


## [0.1.0] - 2026-07-17

### Added
- Repository scaffold (docs, protocol package, mock host, example configs)
- ADR-001 architecture decision (HuanHermes Host protocol + console UI)
- Bridge / Management protocol subset documentation
- Python mock Bridge + Management host for offline UI development
- Python reference Bridge client + unit tests
- Master agent prompt and task board (P0–P3)
