/// 中文 UI 文案（轻量，不引入 gen-l10n 依赖）。
/// 协议字段 / API key / 路径可保留英文。
class AppStrings {
  AppStrings._();

  // ── 导航 ──
  static const appName = 'HuanHermes';
  static const tabSessions = '会话';
  static const tabHost = '主机';
  static const tabTools = '工具';
  static const tabSettings = '设置';

  // ── 通用 ──
  static const refresh = '刷新';
  static const loading = '加载中…';
  static const retry = '重试';
  static const cancel = '取消';
  static const confirm = '确定';
  static const save = '保存';
  static const delete = '删除';
  static const copy = '复制';
  static const copied = '已复制';
  static const export = '导出';
  static const search = '搜索';
  static const more = '更多';
  static const empty = '暂无内容';
  static const error = '出错了';
  static const wrap = '换行';
  static const regex = '正则';
  static const matchCase = '大小写';
  static const autoRefresh = '自动刷新';
  static const pauseRefresh = '暂停刷新';
  static const jumpTop = '回到顶部';
  static const jumpBottom = '跳到底部';
  static const select = '多选';
  static const selectCancel = '取消选择';
  static const pin = '置顶';
  static const unpin = '取消置顶';
  static const archive = '归档';
  static const unarchive = '取消归档';
  static const note = '备注';
  static const rename = '重命名';
  static const filterAll = '全部';
  static const filterPinned = '置顶';
  static const filterRunning = '运行中';
  static const filterArchived = '已归档';
  static const createSession = '新建会话';
  static const openTerminal = '终端';
  static const openChat = '打开会话';
  static const noSessions = '还没有会话';
  static const noSessionsHint = '点右下角新建，或调整筛选条件';
  static const noMatch = '没有匹配结果';
  static const noMatchHint = '试试清空搜索或切换筛选';
  static const connectionShare = '分享连接（不含令牌）';
  static const theme = '主题';
  static const hostStatus = '主机状态';
  static const settings = '设置';
  static const selectedN = '已选';
  static const pinSelected = '置顶所选';
  static const archiveSelected = '归档所选';
  static const deleteSelected = '删除所选';
  static const exportSelected = '导出所选';
  static const copyIds = '复制 ID';
  static const exportMeta = '导出元数据';
  static const copyCsv = '复制 CSV';
  static const sortDir = '排序方向';
  static const clampDetails = '截断详情';
  static const wrapDetails = '换行详情';

  // ── 连接 ──
  static const connectTitle = '连接 Host';
  static const testAndConnect = '测试并连接';
  static const host = '主机';
  static const profileName = '配置名称';
  static const connectFailed = '连接失败';

  // ── 工具宫格 ──
  static const toolsTitle = '工具';
  static const toolsSubtitle = '主机目录与控制台能力';
  static const toolTerminal = '终端';
  static const toolWorkspace = '工作区';
  static const toolSkills = '技能';
  static const toolMcp = 'MCP';
  static const toolCron = '定时任务';
  static const toolMemory = '记忆';
  static const toolAgents = 'Agents';
  static const toolLogs = '日志';
  static const toolActivity = '活动';
  static const toolDiff = 'Diff';
  static const toolPairing = '配对';
  static const toolPermissions = '权限';
  static const toolAudit = '审计';
  static const toolStatus = '状态';

  // ── 聊天 ──
  static const chatInputHint = '输入消息…';
  static const send = '发送';
  static const reconnecting = '重连中…';
  static const reconnected = '已重连';
  static const disconnected = '已断开';
}
