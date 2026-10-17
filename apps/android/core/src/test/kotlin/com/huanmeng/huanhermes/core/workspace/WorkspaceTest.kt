package com.huanmeng.huanhermes.core.workspace

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkspaceTest {
    private fun j(s: String) = Json.parseToJsonElement(s).jsonObject

    @Test fun dirAndFile() {
        val d = Workspace.parseNode(j("""{"path":"src","type":"dir","parent":"","entries":[{"name":"b.kt","type":"file","size":3},{"name":"lib","type":"dir"},{"name":"../x","type":"file"}]}""")) as WsNode.Dir
        assertEquals(listOf("lib", "b.kt"), d.entries.map { it.name })
        assertEquals("", d.parent)
        assertEquals("src/b.kt", Workspace.child(d.path, "b.kt"))
        val root = Workspace.parseNode(j("""{"path":"","type":"dir","entries":[]}""")) as WsNode.Dir
        assertEquals(null, root.parent)
        val f = Workspace.parseNode(j("""{"path":"a.py","type":"file","size":9,"content":"print(1)\n","binary":false}""")) as WsNode.File
        assertEquals("a.py", f.name)
        assertEquals("print(1)\n", f.content)
    }

    @Test fun gitStatus() {
        val g = Workspace.parseGit(j("""{"branch":"main","files":[{"path":"a","status":"M"},{"path":"b","status":"?"},{"status":"M"}]}"""))
        assertEquals("main", g.branch)
        assertEquals(listOf("修改", "未跟踪"), g.files.map { it.label })
    }

    @Test fun unifiedDiffNumbers() {
        val text = "diff --git a/x b/x\nindex 1..2\n--- a/x\n+++ b/x\n@@ -3,3 +3,4 @@ fun\n ctx\n-old\n+new\n+more\n ctx2\n\\ No newline at end of file\n"
        val d = Workspace.parseDiff("x", text)
        assertEquals(1, d.removed); assertEquals(2, d.added)
        val ctx = d.lines.first { it.kind == DiffLine.Kind.Context }
        assertEquals(3, ctx.oldNo); assertEquals(3, ctx.newNo)
        assertEquals(4, d.lines.first { it.kind == DiffLine.Kind.Del }.oldNo)
        assertEquals(listOf(4, 5), d.lines.filter { it.kind == DiffLine.Kind.Add }.map { it.newNo })
        assertEquals(6, d.lines.last { it.kind == DiffLine.Kind.Context }.newNo)
        assertTrue(d.lines.take(4).all { it.kind == DiffLine.Kind.Meta })
        assertEquals(DiffLine.Kind.Meta, d.lines.last().kind)
    }

    @Test fun urlsAndSizes() {
        assertEquals("/workspace?project=p&path=a%20b", Workspace.url("/workspace", "p", "a b"))
        assertEquals("/workspace/git", Workspace.url("/workspace/git", null))
        assertEquals("1.5 KB", Workspace.humanSize(1536))
        assertEquals("kotlin", Workspace.languageOf("A.kt"))
    }
}
