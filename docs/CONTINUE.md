# 新对话接续（短）

把下面 **「粘贴块」** 整段贴进新对话即可。细节以本文件 + `docs/SUBAGENTS.md` + `docs/TASKS.md` + `git log` 为准。

---

## 粘贴块

```text
继续 HuanHermes P4。仓库 /root/huanhermes-app · main。

先读：docs/CONTINUE.md · docs/SUBAGENTS.md · docs/TASKS.md
再：git status -sb && git log -3 --oneline && 核对 pubspec version。

目标：检查状态 → 每轮选 1 个最重要可落地缺口 → 实现 → 验证 → commit + push origin main。
勿重做已 ship（见 TASKS/CHANGELOG/git）。无明确可落地待办 → Goal complete 停止。

铁律：只改本仓；Mock 备用端口（禁 9810/9820）；禁 /.cc-connect；App=控制台；无重依赖；协议先 docs/protocol。
验收：py_compile mock + PYTHONPATH=packages/huan_protocol python3 -m unittest discover -s packages/huan_protocol/test -v（15/15）；Dart bal_aware。
一刀：实现 + pubspec/settings/CHANGELOG/TASKS + push。回报：版本 · SHA · 切片表（短）。

可并行：按 docs/SUBAGENTS.md 用 delegate_task 分轨（不同文件）；主会话 merge + 测 + push。
「继续」= 自动下一刀，P4 已授权。
```

---

## 当前锚点（ship 后请改本段）

| 项 | 值 |
|----|-----|
| 版本 | **0.1.116+116** |
| commit | **`c2d7920`** |
| 下一刀 | **0.1.117** |
| P3 | 收口 |
| P4 | 已授权；真 PTY / 相机 / 真 Hermes 进程 / 系统通知 / 真 file_picker 仍远期 |

## 每轮 6 步

1. status + log + TASKS 扫描  
2. 选缺口（管理面筛选/字段 · MD 安全语法 · Mock 命令；**help/which/type 与 builtins 锁步**）  
3. 实现（零新重依赖）  
4. 验证 15/15 + bal_aware + py_compile  
5. bump 版本 + CHANGELOG + TASKS  
6. commit + `git push origin main`

## 禁区

- 重做 0.1.96–当前已 ship  
- 伪扩 P3 sort / 假称完成真 PTY·相机·真进程  
- 动 live 9810/9820 或 `/root/.cc-connect`  
- 对话明文 token  
