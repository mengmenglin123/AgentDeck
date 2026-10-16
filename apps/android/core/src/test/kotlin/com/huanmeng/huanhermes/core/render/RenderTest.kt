package com.huanmeng.huanhermes.core.render

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownTest {
    @Test fun headingsParagraphsAndInlineStyles() {
        val b = Markdown.parse("# 标题\n\n这是 **粗体**、*斜体*、~~删除~~ 和 `code`，还有 [链接](https://a.b)。")
        assertEquals(2, b.size)
        assertEquals(1, (b[0] as MdBlock.Heading).level)
        val p = (b[1] as MdBlock.Paragraph).text
        fun styled(s: MdStyle) = p.spans.filter { it.style == s }.map { p.text.substring(it.start, it.end) }
        assertEquals(listOf("粗体"), styled(MdStyle.Bold))
        assertEquals(listOf("斜体"), styled(MdStyle.Italic))
        assertEquals(listOf("删除"), styled(MdStyle.Strike))
        assertEquals(listOf("code"), styled(MdStyle.Code))
        assertEquals(listOf("链接"), styled(MdStyle.Link("https://a.b")))
    }

    @Test fun softBreaksStayLineBreaks() {
        val p = (Markdown.parse("第一行\n第二行").single() as MdBlock.Paragraph).text
        assertEquals("第一行\n第二行", p.text)
    }

    @Test fun fencedCodeIncludingUnclosedWhileStreaming() {
        val closed = Markdown.parse("前\n\n```Kotlin\nval a = 1\n```\n后")
        assertEquals(MdBlock.CodeBlock("kotlin", "val a = 1"), closed[1])
        val open = Markdown.parse("```python\nprint(1)\nprint(2")
        assertEquals(MdBlock.CodeBlock("python", "print(1)\nprint(2"), open.single())
    }

    @Test fun nestedAndTaskLists() {
        val b = Markdown.parse("- [x] 完成\n- [ ] 待办\n  1. 子项\n  2. 子项二").single() as MdBlock.ListBlock
        assertEquals(false, b.ordered)
        assertEquals(true, b.items[0].task)
        assertEquals("完成", (b.items[0].blocks[0] as MdBlock.Paragraph).text.text)
        assertEquals(false, b.items[1].task)
        val nested = b.items[1].blocks[1] as MdBlock.ListBlock
        assertTrue(nested.ordered)
        assertEquals(2, nested.items.size)
    }

    @Test fun orderedListStart() {
        val b = Markdown.parse("3. c\n4. d").single() as MdBlock.ListBlock
        assertEquals(3, b.start)
    }

    @Test fun tablesWithAlignment() {
        val t = Markdown.parse("| 名称 | 数量 |\n|:--|--:|\n| a | 1 |\n| b |").single() as MdBlock.Table
        assertEquals(listOf("名称", "数量"), t.header.map { it.text })
        assertEquals(listOf(MdAlign.Start, MdAlign.End), t.align)
        assertEquals(2, t.rows.size)
        assertEquals(2, t.rows[1].size)
    }

    @Test fun quotesRulesImagesAndAutolinks() {
        val b = Markdown.parse("> 引用\n\n---\n\n![图](https://x/y.png)\n\n见 https://example.com/a。")
        assertTrue(b[0] is MdBlock.Quote)
        assertEquals(MdBlock.Rule, b[1])
        assertEquals(MdBlock.Image("图", "https://x/y.png"), b[2])
        val p = (b[3] as MdBlock.Paragraph).text
        assertTrue(p.spans.any { it.style is MdStyle.Link && (it.style as MdStyle.Link).url == "https://example.com/a" })
    }

    @Test fun equalInputGivesEqualBlocks() {
        val src = "# a\n\n- b\n\n```js\nx\n```"
        assertEquals(Markdown.parse(src), Markdown.parse(src))
    }
}

class HighlighterTest {
    private fun kinds(code: String, lang: String) =
        Highlighter.tokenize(code, lang).map { code.substring(it.start, it.end) to it.kind }

    @Test fun kotlinKeywordsStringsComments() {
        val t = kinds("val s = \"if\" // note\nfun f() = 42", "kt")
        assertTrue(("val" to Highlighter.Kind.Keyword) in t)
        assertTrue(("\"if\"" to Highlighter.Kind.Str) in t)
        assertTrue(("// note" to Highlighter.Kind.Comment) in t)
        assertTrue(("42" to Highlighter.Kind.Number) in t)
        assertTrue(t.none { it.first == "if" })
    }

    @Test fun pythonAndShell() {
        assertTrue(("def" to Highlighter.Kind.Keyword) in kinds("def f():\n    return None # x", "python"))
        val sh = kinds("echo \$HOME --verbose # c", "bash")
        assertTrue(("\$HOME" to Highlighter.Kind.Type) in sh)
        assertTrue(("# c" to Highlighter.Kind.Comment) in sh)
    }

    @Test fun diffLines() {
        val t = kinds("@@ -1 +1 @@\n-old\n+new\n same", "diff")
        assertEquals(listOf("@@ -1 +1 @@" to Highlighter.Kind.Meta, "-old" to Highlighter.Kind.Removed, "+new" to Highlighter.Kind.Added), t)
    }

    @Test fun unknownOrHugeStaysPlain() {
        assertTrue(Highlighter.tokenize("x", "brainfuck").isEmpty())
        assertTrue(Highlighter.tokenize("a\n".repeat(Highlighter.MAX_LINES + 2), "kotlin").isEmpty())
    }

    @Test fun tokensNeverOverlap() {
        val code = "/* a \"b\" */ val x = \"/* no */\" // c 'd'\nclass A { fun b() = 'c' }"
        val t = Highlighter.tokenize(code, "kotlin")
        t.zipWithNext().forEach { (a, b) -> assertTrue(a.end <= b.start) }
    }

    @Test fun languageFromPath() {
        assertEquals("kotlin", Highlighter.languageForPath("app/src/Main.kt"))
        assertEquals("python", Highlighter.languageForPath("x/y.py"))
        assertEquals(null, Highlighter.languageForPath("README"))
    }
}

class ToolViewTest {
    @Test fun claudeBashShowsCommandAndUnwrapsTextOutput() {
        val v = ToolView.of("Bash", """{"command":"ls -la","description":"List files"}""", """[{"type":"text","text":"a\nb"}]""")
        assertEquals(ToolView.Kind.Shell, v.kind)
        assertEquals("ls -la", v.command)
        assertEquals("List files", v.title)
        assertEquals("a\nb", v.output)
    }

    @Test fun codexCommandIsAPlainString() {
        val v = ToolView.of("command", "git status", "On branch main")
        assertEquals("git status", v.command)
        assertEquals("On branch main", v.output)
    }

    @Test fun editBecomesALineDiff() {
        val v = ToolView.of("Edit", """{"file_path":"/r/a.kt","old_string":"a\nb\nc","new_string":"a\nB\nc"}""", null)
        assertEquals(ToolView.Kind.Edit, v.kind)
        assertEquals("kotlin", v.language)
        assertEquals(
            listOf(DiffLine.Type.Context, DiffLine.Type.Removed, DiffLine.Type.Added, DiffLine.Type.Context),
            v.diff.map { it.type },
        )
    }

    @Test fun todosAndPlans() {
        val v = ToolView.of("TodoWrite", """{"todos":[{"content":"写测试","status":"completed"},{"content":"发版","status":"in_progress"}]}""", null)
        assertEquals(2, v.todos.size)
        assertEquals("1/2 完成", v.subtitle)
        val p = ToolView.of("update_plan", """{"plan":[{"step":"a","status":"pending"}]}""", null)
        assertEquals("a", p.todos.single().text)
    }

    @Test fun mcpTitleAndGenericFallback() {
        assertEquals("github · create_issue", ToolView.of("mcp__github__create_issue", "{}", null).title)
        val g = ToolView.of("weird_tool", """{"q":"hello"}""", "ok")
        assertEquals(ToolView.Kind.Generic, g.kind)
        assertEquals("hello", g.subtitle)
        assertTrue(g.input!!.contains("\"q\""))
    }

    @Test fun codexFileChangeListsFiles() {
        val v = ToolView.of("file_change", """{"changes":[{"path":"/r/src/a.py","kind":{"type":"update"}},{"path":"/r/b.md","kind":"add"}]}""", null)
        assertEquals(listOf("/r/src/a.py" to "update", "/r/b.md" to "add"), v.files)
    }

    @Test fun applyPatchParsesCodexPatch() {
        val v = ToolView.of("apply_patch", "*** Begin Patch\n*** Update File: x/a.py\n@@\n-a\n+b\n*** End Patch", null)
        assertEquals("a.py", v.subtitle)
        assertEquals(listOf(DiffLine.Type.Meta, DiffLine.Type.Meta, DiffLine.Type.Removed, DiffLine.Type.Added), v.diff.map { it.type })
    }
}
