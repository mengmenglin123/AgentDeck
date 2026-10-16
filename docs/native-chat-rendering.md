# 原生版对话渲染：对标与落地（native 0.2.2）

参考项目（只借鉴设计；AGPL 项目不复制代码）：

| 项目 | 许可 | 借鉴点 |
| --- | --- | --- |
| RikkaHub（Kotlin/Compose LLM 客户端） | AGPL-3.0（仅设计） | 后台线程解析 Markdown、流式时未变块不重组；思考过程折叠 + 计时；长按菜单「选择并复制」独立页；代码块复制；消息统计行（tokens、tok/s、耗时） |
| Happy（Claude Code 移动端，含原生 Android） | MIT | 按工具类型渲染：Bash 命令+输出、Edit/Write/Patch diff、TodoWrite 清单、MCP 标题「server · tool」；大 diff 限制高亮规模、超限回退纯文本 |
| Chatbox / LobeChat / Open WebUI / NextChat | GPL-3.0 / 自定义 / BSD / MIT | GFM 表格横向滚动、代码块语言标签 + 复制 + 折叠长块、回到底部按钮、链接可点 |
| CC Pocket / Claude Code UI | — / AGPL（仅设计） | 工具调用默认一行摘要、点开看详情 |

## 0.2.2 已实现

- Markdown：CommonMark + GFM（表格、任务列表、删除线、裸链接自动识别），解析在 `core`（纯 JVM、有单测），长文本在后台线程解析；段内单换行保留；中文句号不吞进链接。
- 代码块：语言标签、复制按钮、横向滚动、轻量语法高亮（Kotlin/Java/Python/JS/TS/Shell/JSON/YAML/TOML/Go/Rust/C/C++/C#/Swift/Dart/SQL/XML/HTML/CSS/Ruby/PHP/Lua/diff），超过 24 行折叠；超大块（>60k 字符或 >1500 行）不高亮。
- 工具卡：按 Claude Code / Codex / Hermes 的工具形状渲染（终端、编辑 diff、写入、补丁、读取、搜索、任务清单、网页、子任务、MCP、通用 JSON），编辑类与清单默认展开，其余一行摘要。
- 思考过程：进行中显示「思考中… Ns」与最新两行，结束后折叠为「已思考 Ns」，点开看全文。
- 消息长按：复制 / 选择文本 / 分享；Agent 回复改为整宽文档式排版，用户消息保留气泡。
- 回到最新消息按钮；Host 端 Claude 驱动补 `call_id`（工具结果能对上调用）。

## 后续（排期）

- 0.2.3：LaTeX 公式、Mermaid、Markdown 内图片加载、消息内文件路径可点开预览（P2-2）、会话内搜索、导出 Markdown。
- 需 Host 提供用量字段后：消息统计行（tokens、耗时、tok/s）。
