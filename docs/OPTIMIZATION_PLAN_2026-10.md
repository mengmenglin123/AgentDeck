# 优化计划 2026-10（optimize/hark-2026-10）

> 基线：`main@f4ef182`（App 0.1.203）· 2026-10-15。  
> 原则：遵守 README 产品原则——不引入第三方 Host 代码、不做不兼容的协议语义变更、不触碰用户已部署服务与真实密钥。  
> 本轮只做「高价值 + 低风险」项，每项独立小提交并配回归测试。

## 基线审计结论

| 维度 | 发现 |
|------|------|
| 测试 | Python 协议 17 项 / Host 105 项（`unittest`）全绿；但在设置了 `HTTP(S)_PROXY` 的环境里，`test_production_management` 的回环请求会被代理转发，3 项失败（404 而非 401/200）。 |
| 安全 · 鉴权 | `bridge_websocket` 与 `production_management` 用 `hmac.compare_digest(str, str)` 比较 token；客户端发送非 ASCII token 时抛 `TypeError`，Bridge 握手线程直接崩溃而非返回 401。Mock Host 用 `!=` 比较（非恒定时间）。 |
| 安全 · 会话 | Management `DELETE` 在校验 session 是否存在/是否属于该 project **之前**就调用 `close_session`，错误 project 的 DELETE 虽返回 404，却已杀掉另一个项目的运行中 Agent 会话。 |
| 安全 · Companion | `companion_configurator` 先 `write_text`（受 umask 影响，常见为 0644）再 `chmod 600`，含 Bridge/Mgmt token 的临时文件存在可被他人读取的窗口；`data/`、`config/` 目录权限未收紧；`default_project` 未做 TOML 转义。 |
| 安全 · 部署 | 生产 Host 启动时不提示占位 token、过短 token、Bridge/Mgmt 共用 token、非回环地址绑定（Host 自身无 TLS）或配置文件权限过宽。 |
| 安全 · 日志 | Mock Host 的 Mgmt 访问日志会原样打印 `?token=...`。 |
| App 健壮性 | `ChatController` 在 dispose 后仍处理迟到的 Bridge 回调并 `notifyListeners()`（ChangeNotifier 已释放会抛异常）；权限卡片正文只读 `content`/`title`，而 Mock Host 的 `card` 帧使用 `text`，导致卡片显示为 “card”，通知正文也读错字段。 |
| 性能 | `ChatController.isEmpty` 每次都复制整份 transcript；流式 `reply_stream` 每个 delta 都触发一次 `notifyListeners()`（整页重建）。 |
| 代码质量 | `mock_host.py` 5400+ 行 / 224 KB 单文件；`chat_screen.dart` 2500+ 行、`sessions_screen.dart` 2300+ 行；Management Handler 4 处重复鉴权代码；测试中存在重复的 `"server"` 字典键。 |
| 仓库 | `apps/mobile/assets/companion/huanhermes-host-<ver>.tar.gz`（≈105 KB）每次发版提交一份，已有 0.1.201–0.1.203 三份进入历史；且内容由 `test_companion_bundle` 以 sha256 固定。未发现提交的真实密钥。 |
| DX / CI | 没有一键本地校验脚本；CI 的 Python 测试排在 Flutter + Android SDK + NDK 安装之后，反馈慢。 |
| Companion 安装链 | SSH 安装脚本已做 sha256 校验、`umask 077`、仅 https 下载、随机临时路径——整体良好。注意：`configure` 用 `--workspace "$HOME"`，即整个家目录都是 workdir allowlist 根。 |

## 优化计划（按优先级）与完成情况

| # | 项目 | 类别 | 状态 |
|---|------|------|------|
| 1 | Token 比较改为 UTF-8 字节恒定时间比较（新增 `server/token_auth.py`），非 ASCII token 返回 401 而不是崩溃；合并 Management 重复鉴权代码 | 安全/健壮性 | ✅ 已完成 |
| 2 | Management `DELETE` 先校验 session 存在与项目归属，再关闭运行中会话 | Bug/安全 | ✅ 已完成 |
| 3 | Companion 生成 `host.toml` 时以 `O_EXCL` + 0600 创建临时文件、fsync 后原子替换；`config/`、`data/` 收紧为 0700；`default_project` 做 TOML 转义 | 安全 | ✅ 已完成 |
| 4 | 生产 Host 启动安全告警（stderr，非致命，不输出密钥值）：占位/过短 token、两个 token 相同、非回环绑定、配置文件 group/other 可读 | 安全 | ✅ 已完成 |
| 5 | Mock Host：恒定时间 token 比较；日志中 `token=` 与 `Bearer` 值脱敏 | 安全 | ✅ 已完成 |
| 6 | App：`ChatController` dispose 后忽略 Bridge 回调；卡片正文按 `content → text → title` 读取（Reducer 与通知一致）；`isEmpty` 不再复制 transcript | 健壮性/性能 | ✅ 已完成（未经 `flutter analyze` 验证，见下文） |
| 7 | 测试与 DX：回环测试绕过环境代理；新增 `scripts/check.sh`（与 CI 相同的 py_compile + 协议 + Host 测试，可选 `--flutter`）；修复测试重复字典键 | 测试/DX | ✅ 已完成 |
| 8 | CI：新增不依赖 Flutter 的 `python-tests` 快速 job；修复 `setup-android@v3` 默认安装已下架 `tools` 包导致的 build 失败（改为只装 `platform-tools`） | DX | ✅ 已完成（附加 job，不改变现有 build/release/publish 流程） |
| 9 | 流式聊天合并刷新：对 `reply_stream`/`thinking` delta 按帧（~16–33 ms）合并 `notifyListeners()`，并让消息列表按条目局部重建 | 性能 | ⏳ 未做——需要 Flutter 环境跑 widget/controller 测试验证滚动、跳底与搜索高亮行为 |
| 10 | 拆分巨石文件：`mock_host.py` 按 bridge/mgmt/shell-mock 拆模块；`chat_screen.dart`、`sessions_screen.dart` 抽出子组件 | 代码质量 | ⏳ 未做——改动面大，需 Flutter 环境与人工回归 |
| 11 | Companion 安装包不再随每个版本进 git 历史：改为 Release 产物 / Git LFS，App 端继续以 sha256 固定 | 仓库体积 | ⏳ 未做——涉及发布流程与 `publish-companion` job，需维护者决策 |
| 12 | 收窄 SSH 自动配置的 workspace（例如 `~/workspace` 或让用户选择），避免整个 `$HOME`（含 `~/.ssh`、Host 配置）成为 Agent workdir 根 | 安全 | ⏳ 未做——改变产品行为，需要先确认 UX |

## 验证

| 套件 | 优化前 | 优化后 |
|------|--------|--------|
| 协议测试（`packages/huan_protocol/test`） | 17/17 通过 | 17/17 通过 |
| Host 测试（`server/test_*.py`，`PYTHONWARNINGS=error::ResourceWarning`） | 105/105 通过（设置代理时 3 项失败） | 116/116 通过（有无代理均通过） |
| `py_compile` 全部 server / mock / protocol 模块 | 通过 | 通过 |
| Flutter `analyze` / `test` | 本地无 Flutter SDK | 本地未运行（Dart 改动经 tree-sitter-dart 语法检查 0 错误）；PR CI 中 `flutter analyze --no-fatal-infos` 与 `flutter test`（含新增 reducer 单测）均通过 |

本地复现：`./scripts/check.sh`（加 `--flutter` 同时跑 Flutter 门禁）。

## 发布注意

- 本轮 Host 侧修复（`server/*.py`）**不会**自动进入已固定的 `huanhermes-host-0.1.203.tar.gz`；需要在下次发版时重建 Companion 包、提升 `pubspec.yaml` 版本，并同步更新 `test_companion_bundle.py` 中的 sha256 与 `ssh_bootstrap_service.dart` 中的 `archiveSha256`。
- 新增模块 `server/token_auth.py` 会被 `companion_installer` 的 `server/*.py` 规则自动打包，无需额外配置。
- 启动告警只写 stderr（systemd 下进入 journal），不会阻止已有部署启动。
