# 原生版 0.2.3：UI 焕新 + 功能批次 1

来源：`feature-ui-survey.md`（RikkaHub / Happy / CC Pocket / Claude Code UI / Chatbox / LobeChat / Open WebUI 等调研）。只借鉴设计，未复制任何项目代码。

## 已做

- 导航：底部 会话 / 需要我 / 工具 / 设置；“需要我”带待处理数量角标。
- 会话列表：行式布局；状态（需要你 / 运行中 / 有新结果 / 空闲 / 离线，图标+文字，不只靠颜色）、预览、相对时间；
  置顶分组 + 按项目分组的吸顶标题；右滑置顶、左滑归档（归档≠删除，本机保存）；搜索；下拉刷新；
  标题处切换 Host；底部“直接输入第一句话”新建会话；每 20 秒静默刷新状态。
- 需要我：跨所有 Host 汇总待批准权限，就地允许本次 / 本会话允许 / 拒绝；其他 Host 的项会先切换为当前 Host 再发送；
  旧 Host（无 `session_overview`）显示升级提示而不是空列表。
- 输入框：模型 / 模式切换 chip（底层发 `/model`、`/mode`）、斜杠命令面板、输入历史、每会话草稿自动保存；
  运行中输入的消息进入可编辑的队列，本轮 `run_done` 后依次发送，也可“立即发送”；斜杠命令总是立即发送。
  只在 Host 已表明会发 `run_done`（收到过或声明 `session_status`）时排队，旧 Host 行为不变。
- 对话：已完成轮次的思考和工具调用折叠成一行“已工作 · N 次工具调用 · …”，可展开；权限卡显示 待处理 / 已允许 / 本会话已允许 / 已拒绝；
  空会话给出示例提示；连接异常时才出现的状态条 + 诊断面板（检查项、复制诊断信息，令牌自动隐藏）。
- 设置：纯黑深色（OLED）、触感反馈开关、折叠工具调用开关；排版微调。
- 工具页：分组列表替代 17 张占位卡片。
- 依赖：Compose BOM 2025.12.01（M3 1.4）、Kotlin 2.2.21、AGP 8.10.1、compileSdk 36。

## Host / 协议（向后兼容）

- `/sessions` 每项新增可选字段 `status`、`pending_permissions`、`last_message_preview`、`updated_at`（取较新值）；
  `/status` 能力新增 `session_overview`。Flutter 0.1.206 和旧 App 忽略这些字段。
- 生产 Host：`PermissionGate.pending_for()`、`SessionActivity`（挂在 `SessionJournal` 的观察者上，失败不影响投递）。
- Mock Host：同样字段，`/perm` 生成唯一 id 并记录为待处理，`card_action` 后清除。

## 推迟

- 推送通知（UnifiedPush / FCM / 前台服务）与通知内审批 → 下一批。
- @ 文件提及（等 `/workspace/search`）、语音输入、平板双栏、上下文用量表、Plan 审批表单、AskUserQuestion 原生表单。
