# HuanHermes 代码审计与重设计（0.1.181）

> 用当前模型对 `main`（约 0.1.180）全仓复审后的结论与落地路线。  
> 原则：**修根因、保协议兼容、不改渠道/密钥、中文 UI、可验证小步 ship**。

## 1. 现状快照

| 区域 | 规模 | 备注 |
|------|------|------|
| Flutter `lib/` | ~25k 行 Dart（MD 已拆 legacy） | 19 个 Screen，多数 600–2200 行 |
| `mock_host.py` | ~5.3k 行（含 registry） | 终端 mock 巨石；功能完整但难维护 |
| 协议包测试 | 15/15 绿 | 基础协议可信 |
| Flutter 测试 | 7 个文件 | 几乎不覆盖巨型 Screen |
| 版本 | `0.1.184+184` | P0–P3 与大量 P4 切片已 ship |

### 架构（正确部分）

```
App (Flutter) ──WSS Bridge + HTTPS Mgmt──► Host (Mock / 自研)
```

- App **不做** agent loop，真相源在 Host —— 方向对。
- `ConnectionController` / `ChatController` / `MgmtClient` / `BridgeClient` 分层清晰。
- Secure storage、脱敏、审计、offline queue、permission card 等主路径可用。

## 2. 主要问题（按严重度）

### P0 — 结构债

1. **Screen 巨石 + 复制粘贴爆炸**  
   Skills/MCP/Cron/Memory/Activity/Agents/Logs/Diff/Workspace/Dashboard 共享同一模板：
   - `_armTimer` + auto-refresh（14 屏）
   - `_query` / `_queryCase` / `_queryRegex` + FilterChip 堆
   - `Clipboard.setData` + `SnackBar` 手写（每屏 6–24 次）
   - Pull-to-refresh / jump top-bottom / wrap / CSV 导出  
   → 改一处要改十几处；P3/P4 用 FilterChip 堆叠「假深度」。

2. **AppBar 图标过载**  
   Sessions / Connect 顶部 10+ IconButton，移动端不可扫读，与 LiveAgent 级产品感冲突。

3. **中文覆盖极不均**  
   Connect 已中文化；Sessions/Chat 半中文；其余 15+ 屏几乎全英文。与「全部 UI 中文」要求不符。

4. **本地 Store 碎片**  
   `SessionPinsStore` / `Notes` / `Archive` / `Recents` / `ChatDraft` / `TerminalHistory` / `PromptHistory` 各自 `SharedPreferences`，API 风格不一、无统一命名空间封装。

### P1 — 质量与体验

5. **主题薄弱**  
   `AppTheme` 仅 `ColorScheme.fromSeed` + highContrast 边框，缺少 surface 层级、卡片半径、导航指示、输入框圆角等设计 token。

6. **无一级导航壳**  
   功能靠 Sessions overflow / 多级 `Navigator.push` 散落，Discoverability 差。底部导航曾在 commit 消息里提过，代码侧未形成稳定壳。

7. **测试滞后**  
   `widget_smoke_test` 仍断言英文 `Connect to Host` / `Test & connect`（Connect 已改中文 → 测试已过期）。  
   无 golden / 无大屏回归。

8. **MarkdownLite 过重**  
   单文件 2k+ 行 HTML 标签 demo，对控制台价值递减；维护成本高。

9. **mock_host 巨石**  
   200+ 命令 if/elif；help/which/type 锁步脆弱；适合后续拆表驱动，不在本刀大改。

### P2 — 技术债（可后置）

- 多处 `v.toDouble()` 时间戳解析重复。
- Catalog 屏 7–10 个 `_sortBy*` 布尔而非 enum。
- `NotificationService` 点击跳转 TODO。
- CONTINUE 锚点仍写 0.1.179，文档漂移。

## 3. 重设计目标

| 目标 | 说明 |
|------|------|
| **中文优先** | 所有用户可见字符串中文；协议字段/路径可保留英文 |
| **LiveAgent 级主路径** | Connect / Sessions / Chat 清爽、卡片化、信息层级清晰 |
| **导航可发现** | 底部 4 Tab：会话 · 主机 · 工具 · 设置 |
| **共享组件** | 查询匹配、Snack/Copy、Filter 条、空态、加载、AppBar overflow |
| **本地状态统一** | `SessionLocalStore` 门面 |
| **设计 token** | 半径、间距、surface、主色、导航主题 |
| **可验证** | 协议 15/15 + py_compile；烟测与中文对齐 |

**非目标（本阶段不做）**

- 重写 mock 命令表 / 拆 MarkdownLite 全量
- 改 Host 协议或用户侧渠道配置
- 引入重状态管理（Riverpod/Bloc）或 i18n 框架 gen-l10n（先用轻量 `AppStrings`）

## 4. 目标架构（App）

```
lib/
  l10n/app_strings.dart          # 中文文案常量
  theme/app_theme.dart           # 设计 token + M3
  utils/
    query_match.dart             # 文本/正则匹配
    ui_helpers.dart              # snack / copy / haptics
    responsive.dart              # 已有
    security.dart                # 已有
  widgets/
    console_widgets.dart         # 空态、加载、FilterChip 条、section
    markdown_lite.dart
  services/
    session_local_store.dart     # pins/notes/archive/recents 门面
    ... 既有 clients/controllers
  screens/
    home_shell.dart              # 底部导航壳
    tools_hub_screen.dart        # 工具宫格入口
    ... 既有业务屏（逐步瘦身）
```

## 5. 分阶段落地

### Phase A — 基础（本版本 0.1.181）

- [x] 审计文档
- [x] `AppStrings` / `QueryMatch` / `UiHelpers` / `ConsoleWidgets`
- [x] `SessionLocalStore`
- [x] `AppTheme` 升级（圆角卡片、NavigationBar、输入框）
- [x] `HomeShell` + `ToolsHubScreen`
- [x] Sessions 主路径：中文 tooltip、AppBar 收敛到 overflow、接门面 store
- [x] 烟测与版本 bump

### Phase B — Catalog 收敛（0.1.182）

- [x] 抽出 `CatalogUi`（armAutoRefresh / copy / snack / commonActions / 中文标签）
- [x] 14 屏 `_armTimer` → `CatalogUi.armAutoRefresh`
- [x] 8 屏查询 → `QueryMatch`
- [x] 全屏中文化扫尾（Settings/Status/Dashboard/Pairing/Chat/…）
- 完整 `HostCatalogScreen` 配置驱动模板仍可后续深化

### Phase C — Chat / Terminal 体验（0.1.183）

- [x] 工具块默认折叠（设置项 + 气泡展开/收起）
- [x] 权限快捷条 + 权限气泡按钮中文
- [x] Chat/Terminal AppBar 收敛到 overflow
- [x] ListView `cacheExtent` 轻量虚拟化
- [x] 中文扫尾（Chat/Terminal/AppStrings）
- 真实 PTY 仍未接入（协议通道演示 + 明确提示）

### Phase I — 手机 AppBar 扫尾（0.1.189）

- [x] Sessions 多选 / Host 看板 AppBar 收敛
- [x] Tools 宫格手机密度

### Phase H — 手机列表与首连路径（0.1.188）

- [x] Sessions 卡片化列表
- [x] Connect 短路径 + 高级折叠

### Phase G — 手机可用性（0.1.187）

- [x] Connect/Sessions AppBar 收敛
- [x] 触控目标 ≥44px；Chat composer 手机化

### Phase F — UI 设计系统升级（0.1.186）

- [x] AppTheme Linear 风 token（暗色原生 / indigo 强调 / 半透明边框）
- [x] Connect / HomeShell / Chat / console_widgets 主路径视觉现代化

### Phase E — UI 中文与主路径体验（0.1.185）

- [x] 全屏 FilterChip / snack / 菜单中文扫尾（AppStrings 扩展）
- [x] HomeShell 连接状态条（在线指示 + 切换连接）
- [x] AppTheme 页转场 + Dialog/BottomSheet 圆角
- [x] 主机看板健康文案中文化

### Phase D — mock / MD 维护性（0.1.184）

- [x] mock 命令表驱动（`MOCK_TERM_FIXED` + `MOCK_TERM_HANDLERS` + `mock_term_dispatch`）
- [x] catalog 224 命令与 help/which/type 锁步；简单 demo 走 registry，复杂工作区命令仍 elif
- [x] MarkdownLite 核心 vs legacy 分文件（`markdown_lite_legacy.dart`）
- [x] 修 help 双输出 / `import time` 遮蔽 date

## 6. 风险与约束

- 只改本仓；禁 live 9810/9820 与 `/.cc-connect`
- Token 永不进对话/剪贴板公开摘要
- 大屏重构避免「一次改 15 文件却不测」——按模板抽一层再迁
- Flutter SDK 若本机不可用：以 `py_compile` + 协议单测 + 静态审阅为主，CI 出 APK

## 7. 验收清单（0.1.181）

```bash
python3 -m py_compile server/mock-host/mock_host.py packages/huan_protocol/src/*.py
PYTHONPATH=packages/huan_protocol python3 -m unittest discover -s packages/huan_protocol/test -v
# 若有 flutter：
# cd apps/mobile && flutter test
```

- 连接成功后进入 `HomeShell`，底栏 4 Tab 可见
- 工具宫格可打开既有屏
- Sessions AppBar 不再堆 10+ 裸图标
- 烟测断言中文文案
