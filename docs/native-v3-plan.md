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
- [ ] A1 输入历史（每 Host 最近 50 条，长按发送/历史按钮调出）
- [ ] A2 快捷消息 chips（空输入时显示，可在设置编辑）
- [ ] A3 全屏编辑器（长文本展开）
- [ ] A4 回车发送（设置项，默认关）
- [ ] A5 语音输入（系统 SpeechRecognizer，可用时显示麦克风）
- [ ] A6 会话内搜索 + 消息跳转（上一条/下一条我的消息、顶/底）
- [ ] A7 引用回复（长按消息 → 引用到输入框）
- [ ] A8 导出会话为 Markdown（系统分享）
- [ ] A9 代码块行号 / 自动换行设置
### 批次 B · 0.3.1 审查闭环
- [ ] B1 本轮变更文件摘要卡（从 Edit/Write 类工具调用汇总，点开跳 Diff）
- [ ] B2 Diff 行内批注 → 汇总为一条带 path:line 的消息发回会话
- [ ] B3 编辑并重发最近一条消息
### 批次 C · 0.3.2 审批与通知
- [ ] C1 计划审批卡（接受 / 接受并清上下文 / 继续规划+反馈）与 AskUserQuestion 表单（Host card.kind，可选字段）
- [ ] C2 「始终允许」需设备验证（生物识别/锁屏密码）+ 可选 App 锁
- [ ] C3 后台消息未发送看门狗通知（30 秒）
- [ ] C4 长任务进行中通知（Android 16 推广为 Live Update）
### 批次 D · 0.3.3 Host 增强
- [ ] D1 用量/上下文透传（session usage）+ 输入栏用量行
- [ ] D2 卡死检测（N 分钟无输出 → stalled 状态 + 一键中断）
- [ ] D3 发现 Host 上已有的 Claude Code CLI 会话（只读查看，受工作区白名单约束）
- [ ] D4 Steer：运行中「立即转向」（capability steer，Host 中断后注入）
### 批次 E · 0.3.4 系统集成
- [ ] E1 接收系统分享（文本/图片 → 选会话）
- [ ] E2 Host 配置二维码导出/导入（不含 token，导入后走配对码）
- [ ] E3 快捷设置磁贴（待处理数）+ 启动器快捷方式（置顶会话）
- [ ] E4 预设主题 2–3 个
- [ ] E5 预测性返回

## 不做 / 需决策（原因）
- Git 写操作、worktree、新建分支：需 ADR + 用户拍板（当前协议明确只读）。
- 多人同看/分享链接：需中继与公网，安全面大。
- Fork / Side chat / Undo：依赖具体 Agent 能力，Host 驱动未统一。
- FCM：需用户的 Firebase 项目和 Host 端凭据。
- TTS、Mermaid/LaTeX、看板：价值低于上表，1.0 后。
