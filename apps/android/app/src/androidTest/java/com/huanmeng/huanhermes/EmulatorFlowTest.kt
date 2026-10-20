package com.huanmeng.huanhermes

import android.graphics.Bitmap
import android.util.Log
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsNodeInteractionCollection
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.services.storage.TestStorage
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * Drives the real app on an emulator against mock-host running on the CI runner
 * (reached from the emulator as 10.0.2.2). Every step leaves a full-screen
 * screenshot (system bars included, so inset bugs show up) in TestStorage.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class EmulatorFlowTest {
    // No system permission dialog over the UI under test (Android 13+).
    @get:Rule(order = -1) val notifications: org.junit.rules.TestRule =
        if (android.os.Build.VERSION.SDK_INT >= 33) androidx.test.rule.GrantPermissionRule.grant(android.Manifest.permission.POST_NOTIFICATIONS)
        else org.junit.rules.TestRule { base, _ -> base }
    @get:Rule(order = 0) val rule = createAndroidComposeRule<MainActivity>()
    // Inner rule: runs while the activity is still on screen.
    @get:Rule(order = 1) val shotOnFailure = object : TestWatcher() {
        override fun failed(e: Throwable?, description: Description) = shot("FAILED-${description.methodName}")
    }

    private val host = InstrumentationRegistry.getArguments().getString("hostAddr") ?: "10.0.2.2"
    private val api = android.os.Build.VERSION.SDK_INT

    private fun shot(name: String) {
        runCatching {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            val bmp = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
            TestStorage().openOutputFile("api$api-$name.png").use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }.onFailure { Log.w("EmulatorFlowTest", "screenshot $name failed", it) }
    }

    private fun waitText(text: String, substring: Boolean = false, ms: Long = 20_000) =
        rule.waitUntilAtLeastOneExists(hasText(text, substring = substring), ms)

    private fun SemanticsNodeInteractionCollection.count() = fetchSemanticsNodes().size

    private fun field(label: String) = rule.onNode(hasSetTextAction() and hasText(label))

    private fun ensureConnected() {
        rule.waitForIdle()
        if (rule.onAllNodesWithText("还没有连接 Host").count() == 0) return
        rule.onAllNodesWithText("添加 Host").onFirst().performClick()
        waitText("测试并保存")
        shot("02-host-form-empty")
        field("名称").performTextInput("CI mock")
        field("Host（IP、域名或 IPv6）").performTextClearance()
        field("Host（IP、域名或 IPv6）").performTextInput(host)
        field("Bridge 令牌").performTextInput("dev-bridge-token-change-me")
        field("Management 令牌").performTextInput("dev-mgmt-token-change-me")
        shot("03-host-form-filled")
        rule.onNodeWithText("测试并保存").performScrollTo().performClick()
        // Success pops back to the session list with the Host name in the top bar.
        waitText("CI mock")
        rule.waitUntilAtLeastOneExists(hasContentDescription("新建会话"), 20_000)
    }

    private fun openNewChat(title: String) {
        rule.onNodeWithContentDescription("新建会话").performClick()
        waitText("新建会话")
        val chip = hasText("codex") and androidx.compose.ui.test.hasAnyAncestor(androidx.compose.ui.test.isDialog())
        rule.waitUntilAtLeastOneExists(chip, 10_000)
        rule.onNode(chip).performClick()
        field("标题（可选）").performTextInput(title)
        shot("05-new-session-dialog")
        rule.onNodeWithText("创建").performClick()
        rule.waitUntilAtLeastOneExists(androidx.compose.ui.test.hasTestTag("chat-input"), 20_000)
    }

    private fun send(text: String) {
        rule.onNodeWithTag("chat-input").performTextInput(text)
        rule.waitForIdle()
        // Semantic click, not a touch at fixed coordinates: the IME is still animating
        // the input row upwards at this point.
        rule.onNodeWithContentDescription("发送").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick)
    }

    @Test fun a_firstLaunchAddHostAndSessions() {
        rule.waitForIdle()
        shot("01-first-launch")
        ensureConnected()
        shot("04-sessions-connected")
    }

    @Test fun b_chatStreamingPermissionAndRotation() {
        ensureConnected()
        openNewChat("模拟器测试")
        rule.waitUntil(15_000) { rule.onAllNodesWithText("正在连接 Bridge…").count() == 0 }
        shot("06-chat-empty")

        send("你好，模拟器")
        // The long mock reply pushes the user bubble out of the lazy list, so wait on the
        // reply, which echoes the message.
        waitText("收到：你好，模拟器", substring = true, ms = 30_000)
        waitText("— 完成 —", substring = true, ms = 30_000)
        // Markdown: "### Mock markdown" renders as a heading (no hashes) and the fenced block gets a copy button.
        waitText("Mock markdown")
        rule.waitUntilAtLeastOneExists(hasContentDescription("复制代码"), 10_000)
        shot("07-chat-reply")

        send("/perm")
        waitText("需要权限 · 待处理")
        shot("08-permission-card")
        rule.onNodeWithText("拒绝").performClick()
        waitText("Permission denied (mock).", substring = true, ms = 30_000)
        shot("09-permission-denied")
        // run_done after the decision ends the run: the stop button goes away.
        rule.waitUntil(15_000) { rule.onAllNodes(hasContentDescription("停止运行")).count() == 0 }

        // Configuration change keeps the conversation (ViewModel survives).
        rule.activityRule.scenario.recreate()
        waitText("Permission denied (mock).", substring = true)
        shot("10-after-recreate")

        // Back to the list: the new session is there.
        rule.activity.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        waitText("模拟器测试")
        shot("11-sessions-with-new")
    }

    @Test fun b2_inboxComposerAndSessionRows() {
        ensureConnected()
        openNewChat("审批测试")
        rule.waitUntil(15_000) { rule.onAllNodesWithText("正在连接 Bridge…").count() == 0 }
        // Slash palette opens on "/" and closes once a command is picked.
        rule.onNodeWithTag("chat-input").performTextInput("/")
        rule.waitUntilAtLeastOneExists(androidx.compose.ui.test.hasTestTag("slash-palette"), 10_000)
        shot("13-slash-palette")
        rule.onNode(hasText("/status") and androidx.compose.ui.test.hasAnyAncestor(androidx.compose.ui.test.hasTestTag("slash-palette"))).performClick()
        rule.waitUntil(10_000) { rule.onAllNodes(androidx.compose.ui.test.hasTestTag("slash-palette")).count() == 0 }
        rule.onNodeWithContentDescription("发送").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick)
        rule.waitForIdle()
        shot("14-composer-chips")
        // @ mention: the Host's file search fills the picker; picking inserts the path.
        rule.onNodeWithTag("chat-input").performTextInput("看看 @READ")
        rule.waitUntilAtLeastOneExists(androidx.compose.ui.test.hasTestTag("mention-palette"), 10_000)
        shot("14b-mention-palette")
        rule.onAllNodes(hasText("README.md") and androidx.compose.ui.test.hasAnyAncestor(androidx.compose.ui.test.hasTestTag("mention-palette"))).onFirst().performClick()
        rule.waitUntilAtLeastOneExists(hasText("看看 @README.md", substring = true), 5_000)
        rule.onNodeWithTag("chat-input").performTextClearance()

        send("/perm")
        waitText("需要权限 · 待处理")
        rule.activity.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        waitText("审批测试")
        // The session list shows the pending approval as a row status.
        rule.waitUntilAtLeastOneExists(hasText("需要你", substring = true), 20_000)
        shot("15-session-rows")

        rule.onAllNodesWithText("需要我").onFirst().performClick()
        waitText("Mock agent wants to run", substring = true, ms = 20_000)
        shot("16-inbox")
        rule.onAllNodesWithText("拒绝").onFirst().performClick()
        waitText("都处理完了", ms = 30_000)
        shot("17-inbox-done")
        rule.onAllNodesWithText("会话").onFirst().performClick()
        waitText("审批测试")
    }

    @Test fun b3_quickMessagesSearchExport() {
        ensureConnected()
        openNewChat("对标测试")
        rule.waitUntil(15_000) { rule.onAllNodesWithText("正在连接 Bridge…").count() == 0 }
        rule.waitUntilAtLeastOneExists(hasTestTag("quick-messages"), 10_000)
        shot("18-quick-messages")
        rule.onNode(hasText("继续") and androidx.compose.ui.test.hasAnyAncestor(hasTestTag("quick-messages"))).performClick()
        rule.waitUntilAtLeastOneExists(hasText("继续") and hasTestTag("chat-input"), 5_000)
        rule.onNodeWithContentDescription("发送").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick)
        rule.waitForIdle()
        rule.onNodeWithContentDescription("在会话中搜索").performClick()
        rule.onNodeWithTag("chat-search").performTextInput("继续")
        rule.waitUntilAtLeastOneExists(hasText("1/", substring = true), 10_000)
        shot("19-chat-search")
        rule.onNodeWithContentDescription("在会话中搜索").performClick()
        // Goal bar (local) from the ⋮ menu.
        rule.onNodeWithContentDescription("更多").performClick()
        rule.onNodeWithText("设定会话目标").performClick()
        rule.onNodeWithTag("goal-input").performTextInput("把登录模块重构完")
        rule.onNodeWithText("保存").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("goal-strip"), 5_000)
        // A big paste turns into a text attachment and goes out with the message.
        rule.onNodeWithTag("chat-input").performTextInput("日志 ".repeat(1200))
        rule.waitUntilAtLeastOneExists(hasText("转为附件"), 5_000)
        rule.onNodeWithText("转为附件").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("attachment-strip"), 5_000)
        shot("19b-goal-and-attachment")
        rule.onNodeWithTag("chat-input").performTextInput("看看这段日志")
        rule.onNodeWithContentDescription("发送").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick)
        rule.waitUntil(10_000) { rule.onAllNodes(hasTestTag("attachment-strip")).fetchSemanticsNodes().isEmpty() }
        // The mock may answer at once and push the sent bubble off screen (lazy list).
        rule.waitUntil(20_000) { runCatching { rule.onNodeWithTag("chat-list").performScrollToNode(hasText("📎 pasted-", substring = true)); true }.getOrDefault(false) }
        // Plan approval card (plan_cards): keep planning with feedback.
        send("/plan")
        rule.waitUntilAtLeastOneExists(hasTestTag("plan-card"), 15_000)
        shot("20-plan-card")
        rule.onNodeWithText("继续规划…").performScrollTo().performClick()
        rule.onNodeWithTag("plan-feedback").performTextInput("先别动数据库")
        rule.onNodeWithText("发送并继续规划").performClick()
        waitText("已收到反馈", substring = true)
        // AskUserQuestion as a form.
        send("/ask")
        rule.waitUntilAtLeastOneExists(hasTestTag("question-card"), 15_000)
        rule.onNodeWithText("PostgreSQL").performScrollTo().performClick()
        rule.onNodeWithText("登录").performScrollTo().performClick()
        shot("21-question-card")
        rule.onNodeWithText("提交回答").performScrollTo().performClick()
        waitText("已收到回答", substring = true)
        rule.waitUntilAtLeastOneExists(hasTestTag("usage-row"), 10_000)
        rule.activity.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        waitText("对标测试")
        // Claude Code sessions already on the Host (external_sessions).
        rule.onAllNodesWithText("工具").onFirst().performClick()
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-cli 会话")); rule.onNodeWithTag("tool-cli 会话").performClick()
        waitText("重构支付模块", substring = true)
        rule.onNodeWithText("重构支付模块", substring = true).performClick()
        waitText("payment_service.py", substring = true)
        shot("22-external-session")
        rule.onNodeWithContentDescription("返回").performClick()
        rule.onNodeWithContentDescription("返回").performClick()
        rule.onAllNodesWithText("会话").onFirst().performClick()
    }

    @Test fun c_otherTabsAndDarkTheme() {
        ensureConnected()
        rule.onAllNodesWithText("工具").onFirst().performClick()
        rule.waitForIdle(); shot("12-tools")
        // Read-only catalogs (M3): Dashboard, Agents, Logs, Audit (has the deny from test b).
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-dashboard")); rule.onNodeWithTag("tool-dashboard").performClick()
        rule.waitUntilAtLeastOneExists(hasText("运行中"), 15_000)
        rule.waitUntilAtLeastOneExists(hasText("能力", substring = true), 15_000)
        shot("19-dashboard")
        rule.onNodeWithContentDescription("返回").performClick()
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-agents")); rule.onNodeWithTag("tool-agents").performClick()
        waitText("Claude Code")
        shot("20-agents")
        rule.onNodeWithContentDescription("返回").performClick()
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-logs")); rule.onNodeWithTag("tool-logs").performClick()
        rule.waitUntilAtLeastOneExists(hasText("Mock Host", substring = true), 15_000)
        shot("21-logs")
        rule.onNodeWithContentDescription("返回").performClick()
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-audit")); rule.onNodeWithTag("tool-audit").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("catalog-audit"), 10_000)
        rule.waitForIdle(); shot("22-audit")
        rule.onNodeWithContentDescription("返回").performClick()
        // M4: workspace, git diff, terminal.
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-workspace")); rule.onNodeWithTag("tool-workspace").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("ws-entry-README.md"), 15_000)
        shot("23-workspace")
        rule.onNodeWithTag("ws-entry-README.md").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("file-view"), 15_000)
        rule.waitForIdle(); shot("24-file")
        rule.onNodeWithContentDescription("返回").performClick() // up to root
        rule.waitUntilAtLeastOneExists(hasTestTag("ws-entry-README.md"), 15_000)
        rule.onNodeWithContentDescription("返回").performClick() // leave
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-diff")); rule.onNodeWithTag("tool-diff").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("git-file-src/main.py"), 15_000)
        shot("25-git")
        rule.onNodeWithTag("git-file-src/main.py").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("diff-view"), 15_000)
        rule.waitForIdle(); shot("26-diff")
        // Long-press a diff line to add a review comment (lands in the review bar).
        rule.onNodeWithTag("diff-view").performTouchInput { longClick(center) }
        if (runCatching { rule.waitUntilAtLeastOneExists(hasTestTag("review-note"), 3_000); true }.getOrDefault(false)) {
            rule.onNodeWithTag("review-note").performTextInput("改成常量")
            rule.onNodeWithText("添加").performClick()
            rule.waitUntilAtLeastOneExists(hasTestTag("review-bar"), 5_000)
            shot("26b-review-bar")
        }
        rule.onNodeWithContentDescription("返回").performClick()
        // Git write (mock Host has git_write): stage a file, commit it.
        rule.waitUntilAtLeastOneExists(hasTestTag("stage-src/main.py"), 15_000)
        rule.onNodeWithTag("stage-src/main.py").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("commit-bar"), 15_000)
        rule.onNodeWithTag("commit-message").performTextInput("重构登录")
        rule.onNodeWithText("提交").performClick()
        rule.waitUntil(15_000) { rule.onAllNodes(hasTestTag("git-file-src/main.py")).fetchSemanticsNodes().isEmpty() }
        shot("26c-git-committed")
        rule.onNodeWithContentDescription("返回").performClick()
        // Extensions (0.5.0): connect GitHub, probe its tools, create a skill.
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-扩展")); rule.onNodeWithTag("tool-扩展").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("mcp-list"), 15_000)
        rule.onNodeWithTag("ext-tab-2").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("connector-github"), 10_000)
        rule.waitUntilAtLeastOneExists(hasText("接入") and hasAnyAncestor(hasTestTag("connector-github")), 20_000)
        rule.onNode(hasText("接入") and hasAnyAncestor(hasTestTag("connector-github"))).performClick()
        rule.onNodeWithTag("connector-field-token").performTextInput("github_pat_test")
        rule.onNode(hasText("接入") and hasAnyAncestor(isDialog())).performClick()
        rule.waitUntilAtLeastOneExists(hasText("已接入") and hasAnyAncestor(hasTestTag("connector-github")), 15_000)
        shot("27-connectors")
        rule.onNodeWithTag("ext-tab-0").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("mcp-list"), 10_000)
        rule.waitForIdle()
        rule.onNodeWithTag("mcp-list").performScrollToNode(hasTestTag("probe-github"))
        rule.onNodeWithTag("probe-github").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("probe-tools"), 15_000)
        shot("27b-mcp-tools")
        rule.onNodeWithText("好").performClick()
        rule.onNodeWithTag("ext-tab-1").performClick()
        rule.onNodeWithTag("ext-fab").performClick()
        rule.onNodeWithTag("skill-name").performTextInput("deploy-check")
        rule.onNodeWithTag("skill-desc").performTextInput("发布前检查版本号")
        rule.onNodeWithTag("skill-body").performTextInput("1. 看 versionCode")
        rule.onNodeWithText("保存").performClick()
        rule.waitUntil(15_000) { runCatching { rule.onNodeWithTag("skill-list").performScrollToNode(hasTestTag("skill-deploy-check")); true }.getOrDefault(false) }
        rule.onNodeWithTag("skill-deploy-check").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("skill-content"), 10_000)
        shot("27c-skill")
        rule.onNodeWithText("关闭").performClick()
        rule.onNodeWithContentDescription("返回").performClick()
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-终端")); rule.onNodeWithTag("tool-终端").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("terminal-input"), 15_000)
        rule.waitUntil(15_000) { runCatching { rule.onNodeWithTag("terminal-input").assertIsEnabled(); true }.getOrDefault(false) }
        rule.onNodeWithTag("terminal-input").performTextInput("echo native-term")
        rule.onNodeWithTag("terminal-input").performImeAction()
        rule.waitUntilAtLeastOneExists(hasText("native-term") , 15_000)
        rule.waitForIdle(); shot("27-terminal")
        rule.onNodeWithContentDescription("返回").performClick()
        // M5: pairing link with a one-time code, SSH install form.
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-host 连接")); rule.onNodeWithTag("tool-host 连接").performClick()
        waitText("扫码配对")
        rule.onNodeWithText("手动添加 Host").performScrollTo().performClick()
        field("配对链接（可选）").performTextInput("huanhermes://connect?host=$host&bridge=9810&mgmt=9820&tls=0&code=MOCK-PAIR&name=Paired%20mock")
        rule.onNodeWithText("导入配对链接").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("tools-list"), 30_000)
        rule.onAllNodesWithText("会话").onFirst().performClick()
        waitText("Paired mock", ms = 20_000)
        shot("28-paired")
        rule.onAllNodesWithText("工具").onFirst().performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("tools-list"), 10_000)
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-ssh 安装")); rule.onNodeWithTag("tool-ssh 安装").performClick()
        waitText("安装并连接")
        shot("29-ssh-install")
        rule.onNodeWithContentDescription("返回").performClick()
        rule.onAllNodesWithText("设置").onFirst().performClick()
        waitText("外观")
        shot("13-settings")
        rule.onNodeWithText("深色").performClick()
        rule.waitForIdle(); shot("14-settings-dark")
        rule.onAllNodesWithText("会话").onFirst().performClick()
        rule.waitUntilAtLeastOneExists(hasContentDescription("新建会话"), 10_000)
        shot("15-sessions-dark")
        rule.onAllNodesWithText("设置").onFirst().performClick()
        rule.onNodeWithText("跟随系统").performClick()
    }

    @Test fun d_offlineQueueAndReconnect() {
        // `cmd connectivity airplane-mode` needs API 30+; older shells can't cut the network.
        org.junit.Assume.assumeTrue(api >= 30)
        ensureConnected()
        openNewChat("离线测试")
        rule.waitUntil(15_000) { rule.onAllNodesWithText("正在连接 Bridge…").count() == 0 }
        val ui = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun sh(cmd: String) = ui.executeShellCommand(cmd).close()
        try {
            sh("cmd connectivity airplane-mode enable")
            sh("svc wifi disable"); sh("svc data disable")
            // Heartbeat notices the dead socket; banner switches to the reconnect state.
            waitText("已断开", substring = true, ms = 60_000)
            shot("16-offline-banner")
            send("离线时发的消息")
            waitText("等待发送（离线队列）", ms = 10_000)
            shot("17-offline-queued")
        } finally {
            sh("cmd connectivity airplane-mode disable")
            sh("svc wifi enable"); sh("svc data enable")
        }
        rule.waitUntil(90_000) { rule.onAllNodesWithText("等待发送（离线队列）").count() == 0 }
        waitText("收到：离线时发的消息", substring = true, ms = 30_000)
        shot("18-reconnected-flushed")
    }

    /** The bundled Host companion survives packaging byte-for-byte (AAPT must not gunzip it). */
    @Test fun e_companionAssetIntact() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val meta = org.json.JSONObject(ctx.assets.open("companion/companion.json").bufferedReader().readText())
        val bytes = ctx.assets.open("companion/" + meta.getString("file")).readBytes()
        val sha = java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        org.junit.Assert.assertEquals(meta.getString("sha256"), sha)
        org.junit.Assert.assertTrue("not gzip", bytes.size > 2 && bytes[0] == 0x1f.toByte() && bytes[1] == 0x8b.toByte())
    }

    /** Local agent (0.6/0.7): model on mock_agent_env (OpenAI SSE), SSH to its paramiko server, approve, conversations drawer. */
    @Test fun f_localAgentDrivesSshServer() {
        rule.waitForIdle()
        rule.onAllNodesWithText("工具").onFirst().performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("tools-list"), 15_000)
        rule.onNodeWithTag("tools-list").performScrollToNode(hasTestTag("tool-本地 agent")); rule.onNodeWithTag("tool-本地 agent").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("agent-drawer"), 10_000)
        shot("30a-agent-empty")
        rule.onNodeWithTag("agent-drawer").performClick()
        waitText("模型与审批")
        rule.onNodeWithText("模型与审批").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("agent-add-provider"), 10_000)
        rule.onNodeWithTag("agent-add-provider").performClick()
        rule.onNodeWithTag("preset-自定义").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("prov-name"), 10_000)
        rule.onNodeWithTag("prov-name").performTextInput("CI mock")
        rule.onNodeWithTag("llm-base").performTextInput("http://$host:8799/v1")
        rule.onNodeWithTag("llm-key").performTextInput("mock-key")
        rule.onNodeWithTag("prov-fetch").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("prov-model-mock"), 15_000)
        shot("30-agent-model")
        rule.onNodeWithTag("prov-save").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("provider-CI mock"), 10_000)
        rule.onNodeWithTag("agent-current-model").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("pick-mock-large"), 10_000)
        shot("30b-agent-model-picker")
        rule.onNodeWithTag("pick-mock").performClick()
        rule.waitForIdle()
        rule.onNodeWithContentDescription("返回对话").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("agent-drawer"), 10_000)
        rule.onNodeWithTag("agent-drawer").performClick()
        waitText("SSH 服务器")
        rule.onNodeWithText("SSH 服务器").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("agent-servers"), 10_000)
        if (rule.onAllNodes(hasTestTag("agent-server-ci-ssh")).count() == 0) {
            rule.onNodeWithTag("agent-add-server").performClick()
            rule.onNodeWithTag("srv-name").performTextInput("ci-ssh")
            rule.onNodeWithTag("srv-host").performTextInput(host)
            rule.onNodeWithTag("srv-port").performTextClearance()
            rule.onNodeWithTag("srv-port").performTextInput("2222")
            rule.onNodeWithTag("srv-user").performTextInput("hh")
            rule.onNodeWithTag("srv-password").performTextInput("hh-test")
            shot("31-agent-server-form")
            rule.onNodeWithTag("srv-save").performClick()
        }
        rule.waitUntilAtLeastOneExists(hasTestTag("agent-test-ci-ssh"), 10_000)
        rule.onNodeWithTag("agent-test-ci-ssh").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("agent-trust"), 20_000)
        shot("32-agent-hostkey")
        rule.onNodeWithTag("agent-trust").performClick()
        waitText("指纹 ", substring = true, ms = 20_000)
        rule.waitForIdle(); shot("33-agent-servers")
        rule.onNodeWithContentDescription("返回对话").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("agent-input"), 10_000)
        shot("33b-agent-ready")
        rule.onNodeWithTag("agent-skill-chip").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("skill-picker"), 10_000)
        shot("33c-agent-skills")
        rule.onNodeWithTag("skill-ops").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("agent-input").performTextInput("看看服务器")
        rule.onNodeWithTag("agent-send").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.OnClick)
        // `echo … && uname` is not read-only, so the default policy asks first.
        rule.waitUntilAtLeastOneExists(hasTestTag("agent-approve"), 30_000)
        shot("34-agent-approval")
        rule.onNodeWithTag("agent-approve").performClick()
        rule.waitUntil(30_000) { runCatching { rule.onNodeWithTag("agent-list").performScrollToNode(hasText("agent-ok", substring = true) and hasAnyAncestor(hasTestTag("agent-reply"))); true }.getOrDefault(false) }
        rule.waitForIdle(); shot("35-agent-done")
        // Second conversation, then switch back from the drawer.
        rule.onNodeWithTag("agent-new").performClick()
        rule.waitUntilAtLeastOneExists(hasText("看看所有服务器的磁盘和内存"), 10_000)
        rule.onNodeWithTag("agent-drawer").performClick()
        rule.waitUntilAtLeastOneExists(hasText("看看服务器") and hasAnyAncestor(hasTestTag("agent-conversations")), 10_000)
        shot("36-agent-drawer")
        rule.onNode(hasText("看看服务器") and hasAnyAncestor(hasTestTag("agent-conversations"))).performClick()
        rule.waitUntil(15_000) { runCatching { rule.onNodeWithTag("agent-list").performScrollToNode(hasText("agent-ok", substring = true) and hasAnyAncestor(hasTestTag("agent-reply"))); true }.getOrDefault(false) }
        rule.onNodeWithContentDescription("返回").performClick()
    }
}
