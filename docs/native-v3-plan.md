# HuanHermes 原生版 0.3.x 对标增强计划（2026-10-19）

来源：docs/huanhermes-benchmark.md（10-15）、docs/feature-ui-survey.md（10-17）。只借鉴设计，不拷贝代码（AGPL：RikkaHub、CloudCLI）。
协议规则不变：新行为必须由 capability 协商，只加可选字段。

## 已在 0.2.x 完成（对照核销）
seq/resume 断线补发、无限退避重连、会话状态体系+未读、跨 Host 收件箱+列表内审批、UnifiedPush+前台保活+通知内允许/拒绝、
运行中排队（Queue）、斜杠面板、@文件、模式/模型 chips、草稿、连接健康条+诊断、Prompt-first 新建、置顶/归档/搜索/分组、
一轮工作折叠、平板双栏、VT100 终端+按键栏、Diff 异步高亮、扫码配对+每设备 token+证书 pinning+mDNS+SSH 安装（sha256 校验）、
AMOLED/动态色/高对比/字号、Flutter 数据迁移、保持亮屏、等宽字体。

## 待做
### 批次 A · 0.3.0 输入与阅读
- [x] A1 输入历史（每 Host 最近 50 条，长按发送/历史按钮调出）
- [x] A2 快捷消息 chips（空输入时显示，可在设置编辑）
- [x] A3 全屏编辑器（长文本展开）
- [x] A4 回车发送（设置项，默认关）
- [x] A5 语音输入（系统 SpeechRecognizer，可用时显示麦克风）
- [x] A6 会话内搜索 + 消息跳转（上一条/下一条我的消息、顶/底）
- [x] A7 引用回复（长按消息 → 引用到输入框）
- [x] A8 导出会话为 Markdown（系统分享）
- [x] A9 代码块行号 / 自动换行设置
### 批次 B · 0.3.1 审查闭环
- [x] B1 本轮变更文件摘要卡（从 Edit/Write 类工具调用汇总，点开跳 Diff）
- [x] B2 Diff 行内批注 → 汇总为一条带 path:line 的消息发回会话
- [x] B3 编辑并重发最近一条消息
### 批次 C · 0.3.2 审批与通知
- [x] C1 计划审批卡（接受 / 接受并清上下文 / 继续规划+反馈）与 AskUserQuestion 表单（Host card.kind，可选字段）
- [x] C2 「始终允许」需设备验证（生物识别/锁屏密码）+ 可选 App 锁
- [x] C3 后台消息未发送看门狗通知（30 秒）
- [x] C4 长任务进行中通知（Android 16 推广为 Live Update）
### 批次 D · 0.3.3 Host 增强
- [x] D1 用量/上下文透传（session usage）+ 输入栏用量行
- [x] D2 卡死检测（N 分钟无输出 → stalled 状态 + 一键中断）
- [x] D3 发现 Host 上已有的 Claude Code CLI 会话（只读查看，受工作区白名单约束）
- [x] D4 Steer：运行中排队消息的「立即发送」直接注入当前轮（production Host 运行中收到消息即写入 Agent stdin），无需新协议
### 批次 E · 0.3.4 系统集成
- [x] E1 接收系统分享（文本/图片 → 选会话）
- [x] E2 Host 配置二维码导出/导入（不含 token，导入后走配对码）
- [x] E3 快捷设置磁贴（待处理数）+ 启动器快捷方式（置顶会话）
- [x] E4 预设主题 2–3 个
- [x] E5 预测性返回

## 不做 / 需决策（原因）
- Git 写操作、worktree、新建分支：需 ADR + 用户拍板（当前协议明确只读）。
- 多人同看/分享链接：需中继与公网，安全面大。
- Fork / Side chat / Undo：依赖具体 Agent 能力，Host 驱动未统一。
- FCM：需用户的 Firebase 项目和 Host 端凭据。
- TTS、Mermaid/LaTeX、看板：价值低于上表，1.0 后。

## 交付
- 0.3.0 @19818b9（编译失败，已修）→ 0.3.1 @8358b94 → **0.3.2 @d86c7bd，tag native-v0.3.2-rc1，versionCode 2014**，API 26/34 模拟器全绿（7 个用例，含快捷消息/搜索/计划卡/提问表单/用量行/CLI 会话截图）。
- APK：apks/huanhermes-native-0.3.2-rc1.apk，sha256 15e6acbf…，证书 fb220e0970ca5764。
- 新协议能力（v2 opt-in，Flutter 0.1.206 不受影响）：plan_cards、usage；Management：external_sessions（/external-sessions）。
- 未在模拟器覆盖：Diff 长按批注（测试为条件分支）、语音（模拟器无识别服务）、设备验证/App 锁（模拟器无锁屏）、磁贴/快捷方式、系统分享。需真机验证。

# 0.4.x 丰富功能批次（2026-10-19，用户：“都继续完成推进，丰富功能”）
- [x] F1 附件：拍照 / 相册 / 文件 / 剪贴板图片（≤4 个、单个 5 MB、共 10 MB，大图自动压到 2048px JPEG）；production Host 保存到 `<workdir>/.huanhermes/uploads`（自带 .gitignore）并把路径附在消息后（server/uploads.py；Bridge 帧上限默认 16 MB）
- [x] F2 粘贴超过 3000 字时询问“转为附件”
- [x] F3 朗读回复（系统 TTS，长按消息 → 朗读）
- [x] F4 Git 写操作：暂存 / 取消暂存 / 提交 / 推送；Host 端默认关闭，`[workspace] git_write = true` 才开启（capability git_write，server/workspace_git_write.py，固定参数无 shell、路径限制在工作区、push 不弹凭据、写入活动流）；推送前二次确认 + 设备验证
- [x] F5 定时提示：会话 ⋮ →「定时发送…」，每天 HH:MM 或每 N 小时；手机 WorkManager 按时发送（任何 Host 都能用），工具页「定时提示」管理
- [x] F6 设置导出 / 导入（JSON，不含令牌与推送地址）
- [x] F7 桌面小部件「需要我」（待处理数，点按打开）
- [x] F8 会话目标条（本机保存，可一键发给 Agent）
- 延后：终端多标签、Mermaid/LaTeX、Fork/Undo（依赖 Agent）、多人同看、FCM（需 Firebase）
