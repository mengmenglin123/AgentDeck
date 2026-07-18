# 新对话接续（短 · 偏松）

把下面 **「粘贴块」** 整段贴进新对话即可。细节按需再读 `docs/SUBAGENTS.md` · `docs/TASKS.md` · `git log`。

---

## 粘贴块

```text
继续 HuanHermes P4。/root/huanhermes-app · main。
先 git status && git log -3 --oneline，需要时再读 docs/CONTINUE.md、docs/SUBAGENTS.md、docs/TASKS.md。

每轮：找一个（或几个不撞文件的）可落地缺口 → 做完 → 15/15 + py_compile → bump 版本/CHANGELOG/TASKS → commit + push main。
已 ship 别重做；只剩真 PTY/相机/真 Hermes/系统通知/真 file_picker 时说 Goal complete 并停。

硬限制：只改本仓；禁 9810/9820 与 /.cc-connect；无重依赖；token 不进对话。
能并行就 delegate_task 分文件；主会话负责合并、测试、push。
「继续」= 直接干，P4 已授权。短回报即可。
```

---

## 当前锚点（功能 ship 后可改；也可只信 git）

| 项 | 值 |
|----|-----|
| 功能版本 | **0.1.151+151** |
| 功能 commit | **`9f0c310`** |
| HEAD 文档 | 含 CONTINUE 松版（见 git log） |
| 下一功能刀 | **0.1.152** |
| P3 | 收口 |
| P4 | 已授权；真 PTY / 相机 / 真 Hermes 进程 / 系统通知 / 真 file_picker 仍远期 |

## 每轮（灵活）

1. `git status` + `git log`；需要再扫 TASKS  
2. 选 1 个，或 2–3 个**不撞文件**的小切片  
3. 实现（零新重依赖；mock 的 help/which/type 与 builtins 尽量锁步）  
4. 验证：15/15 + py_compile；Dart 改动建议 bal_aware  
5. bump：pubspec + settings + CHANGELOG + TASKS（CONTINUE 锚点可几刀一更）  
6. commit + `git push origin main`  
7. 短回报：版本 · SHA · 做了啥  

## 硬限制（别松）

- 只改本仓  
- 禁 live **9810/9820**；禁 `/root/.cc-connect`  
- 不重做已 ship；不假装完成真 PTY / 相机 / 真进程 / 系统通知 / 真 file_picker  
- token 不进对话  

## 可松

- 一刀多个不撞文件切片 OK  
- 小改不必强行 delegate_task  
- 子代理改代码即可；**push / 版本号主会话**  
- CONTINUE 锚点不必每刀必改  
