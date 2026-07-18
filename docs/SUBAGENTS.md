# 子代理并行（Hermes `delegate_task`）

目标：主会话只做 **scan → 派工 → merge → 测 → push**；实现细节丢给 leaf 子代理，加速且少污染上下文。

## 何时并行

| 可并行（不同文件） | 必须串行（同文件/同分支逻辑） |
|--------------------|-------------------------------|
| A: `markdown_lite.dart` | 同一 screen 的多处 UI 结构 |
| B: `mock_host.py` 新 builtin | mock 里同一 `elif` 链插入点冲突 |
| C: 某 `*_screen.dart` 筛选 chips | pubspec / CHANGELOG / TASKS 版本（只主会话写） |
| 只读审查 / 扫描 | 最终 unittest + push |

最多同时 **2–3** 路（本机并发上限）；**禁止** 两个子代理改同一文件。

## 主会话流程（一刀）

```text
1. Scan：git log + TASKS → 选定 0.1.N 的 2–3 个互不撞文件的切片
2. 并行 delegate_task（leaf）：每路 goal 写清路径、验收、禁止项
3. 收回结果：主会话自己打开 diff 核对（子代理 self-report 不可全信）
4. 主会话：bal_aware + py_compile + 15/15
5. 主会话独占：pubspec / settings 版本 / CHANGELOG / TASKS
6. commit + push；更新 CONTINUE.md 锚点版本/SHA
```

## 派工模板（复制改）

### 轨 A — MarkdownLite

```text
goal: 在 apps/mobile/lib/widgets/markdown_lite.dart 增加 <SLICE>；零新 pub 依赖。
context: 仓库 /root/huanhermes-app。已有 callouts/details/footnotes/h4/abbr/spoiler/kbd… 勿重做。
改完 bal_aware 括号平衡；不要碰 mock_host / pubspec / CHANGELOG。
回报：改了哪些符号、如何自测、文件路径。禁止 commit。
```

### 轨 B — Mock terminal

```text
goal: server/mock-host/mock_host.py 增加 builtins: <cmds>；help/which/type 锁步；插在 echo 分支之前。
context: 禁 9810/9820；勿改 /.cc-connect。对照已有 tr/rev/cmp/yes/tee/xargs 风格。
py_compile 通过。不要碰 Dart / pubspec。禁止 commit。
回报：命令列表 + 示例输入输出。
```

### 轨 C — 某一屏筛选/字段

```text
goal: apps/mobile/lib/screens/<screen>.dart 增加 <chips/字段>，对齐现有 FilterChip 模式（all/具体/other）。
context: 只读 Host JSON；复制仅 metadata。不要碰 markdown_lite / mock 除非缺字段（缺则只报缺口）。
bal_aware；禁止 commit。
```

### 轨 R — 只读审查（实现后）

```text
goal: 审查本刀 diff 是否撞车/回归/泄密；列出必须修项。
context: git diff --stat + 指定文件。不改文件。
```

## 主会话合并清单

- [ ] 无两路改同一 path  
- [ ] mock：`help` 文案含新命令；`known`/`builtins` 同步  
- [ ] Dart：`bal_aware` → (0,0,0)  
- [ ] `py_compile` mock + protocol  
- [ ] unittest **15/15**  
- [ ] 版本三处一致（pubspec / settings / CHANGELOG）  
- [ ] TASKS 勾选新 P4 切片 ID  
- [ ] push `origin main`  
- [ ] 刷新 `docs/CONTINUE.md` 锚点  

## 反模式

- 子代理 `git push` / 改版本号（版本只主会话）  
- 子代理「顺手」重构无关文件  
- 为并行而拆会互相依赖的 API 变更（先协议 PR，再两边实现）  
- 把真 PTY/相机/真进程塞进并行小刀假装完成  

## 与 standing goal 的关系

用户「继续」→ 主会话按 CONTINUE 开刀；有 2+ 不撞文件切片时 **必须倾向 delegate_task 并行**，最后主会话验收 push。  
