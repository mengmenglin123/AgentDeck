package com.huanmeng.huanhermes.core.agent

/**
 * Built-in skill packs: a role prompt the local agent adds to its system
 * prompt, plus starter prompts for the empty screen. [icon] names a Material
 * icon the app maps to a vector.
 */
data class SkillPack(
    val id: String,
    val name: String,
    val icon: String,
    val description: String,
    val prompt: String,
    val starters: List<String>,
)

object SkillPacks {
    val all = listOf(
        SkillPack("ops", "服务器运维", "dns", "通过 SSH 查看、排障、修改你的服务器",
            "当前技能：服务器运维。优先用 SSH 工具。先只读排查（状态、日志、资源），给出结论再动手；改配置前先备份，危险操作先说明影响。",
            listOf("看看所有服务器的磁盘和内存", "nginx 为什么起不来？", "最近 1 小时的错误日志", "把系统更新一下")),
        SkillPack("research", "联网研究", "travel_explore", "搜索并阅读网页，带来源地总结",
            "当前技能：联网研究。先用 web_search 找到 2–4 个可靠来源，再用 web_fetch 阅读原文；回答时写清结论，并在末尾列出引用的网址。不要编造来源。",
            listOf("帮我调研一下最近的 Kotlin 2.x 新特性", "对比几款主流的开源 LLM 推理框架", "今天有什么重要的科技新闻？")),
        SkillPack("docs", "文档助手", "description", "阅读附件里的 PDF、Word、Excel，总结、提问、提取",
            "当前技能：文档助手。用户的附件已经把文本放在消息里。先给出 3–5 句的概要，再按用户的要求提取要点、表格或回答问题；引用时注明出处段落。内容被截断时告诉用户。",
            listOf("总结这份文档的要点", "把文档里的表格整理成 Markdown", "这份合同有哪些需要注意的条款？")),
        SkillPack("code", "代码审查", "code", "审查代码、解释报错、给出修改建议",
            "当前技能：代码审查。按严重程度列出问题（bug、安全、性能、可读性），每条给出位置、原因和修改后的代码。需要验证小段逻辑时可以用 run_javascript。",
            listOf("帮我审查这段代码", "解释一下这个报错", "这个正则对吗？帮我测一下")),
        SkillPack("calc", "计算与数据", "calculate", "精确计算、单位换算、数据整理",
            "当前技能：计算与数据。任何需要精确结果的计算都用 run_javascript 执行而不是心算，并展示关键步骤。日期相关先调用 current_time。",
            listOf("房贷 100 万 30 年 3.1% 等额本息每月多少？", "离今年春节还有几天？", "把这组数据算一下均值和标准差：12, 15, 9, 22, 18")),
        SkillPack("translate", "翻译润色", "translate", "中英互译、改写、润色",
            "当前技能：翻译润色。保持原意和语气，术语准确；中文译文要自然。用户给中文默认译成英文，给其他语言默认译成中文。润色时先给结果，再用一两句说明改了什么。",
            listOf("把这段话翻译成英文", "帮我润色这封邮件", "用更正式的语气改写")),
        SkillPack("writing", "写作", "edit_note", "写周报、文案、提纲、邮件",
            "当前技能：写作。先确认受众和用途（如果用户没说就按最常见的场景写），结构清晰、段落短；给出可以直接使用的成稿。",
            listOf("帮我写一份本周工作周报", "写一段产品更新说明", "给我一个技术分享的提纲")),
    )

    fun find(id: String?): SkillPack? = all.firstOrNull { it.id == id }
}
