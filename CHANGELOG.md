# Changelog

## 0.1.170

- Agent event notifications: permission request, task error, disconnect
- Permission request notification when agent needs approval
- Task error notification on agent failure
- Bridge disconnect notification with reconnect hint
- NotificationService integration in ChatController


## 0.1.169

- Git actions: commit/push/pull from workspace screen
- Git commit dialog with message input
- Git push/pull with success/failure feedback
- Mock git endpoints: POST /workspace/git/commit, /push, /pull
- MgmtClient: gitCommit(), gitPush(), gitPull() methods


## 0.1.168

- Permissions screen: pending/approved/denied permission management
- Auto-approve rules: configure tools to skip permission prompts
- Permission badge on chat AppBar: shows pending count
- Mock /perm command: sends permission request card with Allow/Deny buttons
- Competitive gap analysis: 8 features identified vs CodeAgent Mobile/tlbx/codex-tg


## 0.1.167

- Hermes adapter detection: show Mock vs Real Hermes in settings
- ConnectionController.adapterType / isRealHermes getters
- Settings dynamically displays connected host type
- App compatible with both mock and real Hermes hosts


## 0.1.166

- Real PTY support: HUAN_REAL_PTY=1 enables real shell with PTY
- RealPtyManager: spawn/resize/cleanup real shell processes
- Terminal resize forwarded to real PTY via ioctl
- Falls back to mock when HUAN_REAL_PTY not set


## 0.1.165

- QR code generation on pairing screen (share connection via QR)
- QR code scanner on connect screen (scan to import pairing URI)
- Added qr_flutter + mobile_scanner packages
- Updated all "future P4" references to live features


## 0.1.164

- System notifications: flutter_local_notifications + Android POST_NOTIFICATIONS permission
- File picker: real file/image picking from device storage, gallery, or camera
- Image picker: camera and gallery integration for image attachments
- Notification service: task completion + error alerts with channel support
- File picker service: unified file/image/video picking interface


## 0.1.163

- Refactor: remove 25 duplicate elif handler blocks (-73 lines)
- Fix: resolve 8 Dart analyzer warnings (unnecessary type checks/casts/null assertions)
- Fix: remove unused _copyStatus from _StatChip
- Fix: dedup known/builtins sets (193 unique entries)


## 0.1.162

- Fix: mock df/free/ps/uptime handlers (were in help but missing)


## 0.1.161

- Newest FilterChips on activity/logs/memory screens


## 0.1.160

- Mock ip/netstat/traceroute (+ help/which/type lockstep)
- Handler cleanup (subagent refactored to compact form)


## 0.1.159

- Mock 22 commands: shell/archive/network + editors/system/admin
- Mock bash/sh/exit/logout/source/set (+ help/which/type lockstep)
- Mock tar/gzip/gunzip/zip/unzip (+ help/which/type lockstep)
- Mock curl/wget/ssh/scp/rsync/ping (+ help/which/type lockstep)
- Mock man/info/vi/nano/screen/tmux (+ help/which/type lockstep)
- Mock mount/umount/dd/service/systemctl/lsblk/fdisk (+ help/which/type lockstep)
- Mock at/cron/crontab/useradd/userdel/usermod/groupadd/groupdel/mail (+ help/which/type lockstep)

## 0.1.158

- Mock cp/mv/rm/chmod/chown/chgrp (+ help/which/type lockstep)
- Mock less/more/awk/sed (+ help/which/type lockstep)
- Mock kill/jobs/bg/fg (+ help/which/type lockstep)

## 0.1.157

- Auto refresh FilterChips on skills/status/workspace screens (completes all screens)
- MarkdownLite `<footer>` + `<hgroup>`
- Mock true/false/unset (+ help/which/type lockstep)

## 0.1.156

- Auto refresh FilterChips on mcp/memory/sessions screens
- MarkdownLite `<section>` + `<article>` + `<header>`
- Mock ulimit/finger/nologin (+ help/which/type lockstep)

## 0.1.155

- Auto refresh FilterChips on diff/host_dashboard/logs screens
- MarkdownLite `<main>` + `<aside>` + `<nav>`
- Mock lastb/faillog/chage (+ help/which/type lockstep)

## 0.1.154

- Auto refresh FilterChips on activity/agents/audit/cron screens
- MarkdownLite `<figcaption>` + `<map>`
- Mock history/alias/unalias (+ help/which/type lockstep)

## 0.1.153

- Terminal view Find FilterChip
- MarkdownLite `<progress>` + `<figure>`
- Mock chsh/passwd/lastlog (+ help/which/type lockstep; demo-only)

## 0.1.152

- Diff view Line# FilterChip
- MarkdownLite `<slot>` + `<meter>`
- Mock su/sudo/chfn (+ help/which/type lockstep; demo-only auth failure)

## 0.1.151

- Terminal view FilterChips (regex / case; wrap already present)
- MarkdownLite `<dialog>` + `<template>`
- Mock write/wall/newgrp (+ help/which/type lockstep)

## 0.1.150

- Diff view FilterChips (wrap / regex / case)
- MarkdownLite `<iframe>` + `<portal>`
- Mock id/login/mesg (+ help/which/type lockstep)

## 0.1.149

- Chat view FilterChips (wrap / regex / case)
- MarkdownLite `<math>` + `<area>`
- Mock stty/uname/hostname (+ help/which/type lockstep)

## 0.1.148

- Skills view FilterChips (wrap / regex / case)
- MarkdownLite `<canvas>` + `<svg>`
- Mock toe/reset/resize (+ help/which/type lockstep)

## 0.1.147

- Agents view FilterChips (wrap / regex / case)
- MarkdownLite `<audio>` + `<picture>`
- Mock script/scriptreplay/infocmp (+ help/which/type lockstep)

## 0.1.146

- Cron view FilterChips (wrap / regex / case)
- MarkdownLite `<track>` + `<video>`
- Mock tput/tset/tabs (+ help/which/type lockstep)

## 0.1.145

- Workspace view FilterChips (wrap / regex / case)
- MarkdownLite `<object>` + `<param>`
- Mock base64/md5sum/dircolors (+ help/which/type lockstep)

## 0.1.144

- MCP view FilterChips (wrap / regex / case)
- MarkdownLite `<noframes>` + `<embed>`
- Mock base32/sha224sum/sha384sum (+ help/which/type lockstep)

## 0.1.143

- Host dashboard FilterChips (wrap / regex / case)
- MarkdownLite `<applet>` + `<noembed>`
- Mock diff3/pr/sha512sum (+ help/which/type lockstep)

## 0.1.142

- Activity view FilterChips (wrap / regex / case)
- MarkdownLite `<frame>` + `<frameset>`
- Mock diff/patch/sdiff (+ help/which/type lockstep)

## 0.1.141

- Sessions view FilterChips (wrap / regex / case)
- MarkdownLite `<bgsound>` + `<multicol>`
- Mock getopt/strings/csplit (+ help/which/type lockstep)

## 0.1.140

- Logs view FilterChips (wrap / regex / case)
- MarkdownLite `<nextid>` + `<keygen>`
- Mock mkdir/rmdir/mkfifo (+ help/which/type lockstep)

## 0.1.139

- Memory view FilterChips (wrap / regex / case)
- MarkdownLite `<isindex>` + `<spacer>`
- Mock printf/realpath/touch (+ help/which/type lockstep)

## 0.1.138

- Status view FilterChips (wrap / regex / case)
- MarkdownLite `<dir>` + `<menu>`
- Mock ldconfig/uuidgen/seq (+ help/which/type lockstep)

## 0.1.137

- Chat search/tools FilterChips (regex / case / tools)
- MarkdownLite `<plaintext>` + `<basefont>`
- Mock capsh/runcon/ldd (+ help/which/type lockstep)

## 0.1.136

- Audit view FilterChips (wrap / regex / case / newest)
- MarkdownLite `<xmp>` + `<listing>`
- Mock unshare/nsenter/setpriv (+ help/which/type lockstep)

## 0.1.135

- Connect query FilterChips (wrap / regex / case)
- MarkdownLite `<blink>` + `<marquee>`
- Mock taskset/prlimit/chroot (+ help/which/type lockstep)

## 0.1.134

- Settings pref FilterChips (wrap / regex / case)
- MarkdownLite `<acronym>` + `<nobr>`
- Mock stdbuf/flock/ionice (+ help/which/type lockstep)

## 0.1.133

- Pairing view FilterChips (wrap / regex / case / sort / auto)
- MarkdownLite `<wbr>` + `<rp>`
- Mock nice/nohup/watch (+ help/which/type lockstep)

## 0.1.132

- Terminal view FilterChips (wrap / newest / timestamps)
- MarkdownLite `<font>` + `<center>`
- Mock install/shred/timeout (+ help/which/type lockstep)

## 0.1.131

- Chat permission role filter chip
- MarkdownLite `<ruby>` + `<rt>`
- Mock link/ln/truncate (+ help/which/type lockstep)

## 0.1.130

- Audit action chips expand (host/git/settings/terminal/other)
- MarkdownLite `<bdi>` + `<bdo>`
- Mock pathchk/mktemp/sync (+ help/which/type lockstep)

## 0.1.129

- MCP kind filter chips
- MarkdownLite `<time>` + `<data>`
- Mock dir/vdir/tsort (+ help/which/type lockstep)

## 0.1.128

- Logs logger filter chips
- MarkdownLite `<br>` + `<strike>`
- Mock unexpand/tac/namei (+ help/which/type lockstep)

## 0.1.127

- Skills tag filter chips
- MarkdownLite HTML `<mark>`
- Mock cksum/sum/expand (+ help/which/type lockstep)

## 0.1.126

- Diff path-prefix filter chips
- MarkdownLite `<big>` + `<tt>`
- Mock locale/umask/readlink (+ help/which/type lockstep)

## 0.1.125

- Workspace extension filter chips
- MarkdownLite `<code>` + `<i>`
- Mock join/split/getent (+ help/which/type lockstep)

## 0.1.124

- Cron last_status filter chips
- MarkdownLite `<strong>` + `<b>`
- Mock paste/column/comm (+ help/which/type lockstep)

## 0.1.123

- Host dashboard value-type filter chips
- MarkdownLite `<dfn>` + `<em>`
- Mock lscpu/fmt/shuf (+ help/which/type lockstep)

## 0.1.122

- Agents platform filter chips
- MarkdownLite `<var>` + `<samp>`
- Mock w/last/cal (+ help/which/type lockstep)

## 0.1.121

- Sessions platform filter chips
- MarkdownLite `<cite>` + `<q>`
- Mock users/tty/who (+ help/which/type lockstep)

## 0.1.120

- Status value-type filter chips
- MarkdownLite `***` bold-italic + `<small>`
- Mock printenv/logname/groups (+ help/which/type lockstep)

## 0.1.119

- Agents model filter chips
- MarkdownLite `<ins>` + `<s>`
- Mock arch/getconf/numfmt (+ help/which/type lockstep)

## 0.1.118

- Agents adapter filter chips
- MarkdownLite h6 + `<del>`
- Mock nproc/factor/bc (+ help/which/type lockstep)

## 0.1.117

- Activity source filter chips + diversified seed sources
- MarkdownLite h5 + `<u>` underline
- Mock od/expr/test (+ type/which/help lockstep)

## 0.1.116

- Sessions agent_type filter chips
- Cron kind filter chips
- MarkdownLite h4 + `<abbr title>`
- Mock yes/tee/xargs

## 0.1.115

- Memory tag filter chips
- MarkdownLite footnotes `[^id]` / `[^id]:`
- Mock tr/rev/cmp terminal builtins

## 0.1.114

- Logs source filter chips + API `source` query
- MarkdownLite `<sup>` / `<sub>`
- Mock fold/hexdump/xxd/jq; richer log seeds

## 0.1.113

- Skills category filter chips
- MarkdownLite `||spoiler||` (blacked-out text)
- Mock md5sum/sha1sum/sha256sum, nl, cut

## 0.1.112

- MCP enabled filter chips + catalog enabled flags
- MarkdownLite `<details>/<summary>` ExpansionTile
- Mock base64/file/uniq/type terminal builtins

## 0.1.111

- Activity level filter chips (info/warn/error/debug)
- Agents subtitle shows adapter/process; hermes agent mock fields
- Mock date +FMT, sort/export/env session vars; head/tail -n

## 0.1.110

- Status screen Bridge adapters list + copy summary
- MarkdownLite `<kbd>` keys
- Mock terminal grep/find/seq over workspace tree

## 0.1.109

- Chat in-app SnackBar on silent Reconnected
- Workspace source files preview via MarkdownLite fenced highlight
- Mock sleep/touch/history + hermes project caps deepen

## 0.1.108

- MarkdownLite bare URL autolink (console-safe)
- Diff file chips status-colored avatars
- Workspace .md preview via MarkdownLite
- Mock terminal true/false/printf + help

## 0.1.107

- MarkdownLite `==mark==` highlight
- Mock terminal basename/dirname/realpath/stat/du + which/help

## 0.1.106

- MarkdownLite GitHub-style callouts (`> [!NOTE]` / TIP / WARN / IMPORTANT)
- Mock terminal tree/df/free/ps/uptime
- Audit action-prefix filter chips (bridge/session/chat/permission)

## 0.1.105

- MarkdownLite image `![alt](url)` console-safe alt chip (no network)
- Mock terminal which/head/tail/wc + cat from workspace tree
- Host dashboard hermes adapter chip + copy metadata

## 0.1.104

- Mock terminal cd/mkdir (readonly tree) + help; workdir-aware ls
- Terminal input hint shows local workdir track
- Activity list level/source + seed levels; filter includes them

## 0.1.103

- Mock workspace hermes/ + docs/protocol; git status + diffs
- Terminal ls dynamic from workspace tree
- Logs show source/logger; code block header line count

## 0.1.102

- MarkdownLite ordered lists + multi-line blockquotes
- Attach dialog presets (note/md/json/log) + mime by extension
- Mock hermes cron jobs, host log seed, terminal clear/reset
- Cron UI shows project/tags when present

## 0.1.101

- Settings terminal font scale (device-local) wired into Terminal screen
- Mock memory hermes entries + tags in Memory UI; MCP hermes-memory/skills catalog
- Mock agents claude-code/codex capabilities + MCP kind/note fields

## 0.1.100

- MarkdownLite strikethrough ~~text~~ (P4-5)
- Agents subtitle note + capabilities; Status hermes adapter chip (P4-3)
- In-app permission SnackBar (not system notifications) (P4-4)
- Mock status hermes block + activity seed events (P4-3/P4-4 surface)

## 0.1.99

- MarkdownLite task lists + richer link display (P4-5)
- Terminal AppLifecycle resume reconnect + Reconnect action (P4-4)
- Pairing “Copy paste card” for Connect import (P4-2)
- Mock skills category/version/tags + Skills UI meta; hermes reply task/link demo (P4-3)

## 0.1.98

- MarkdownLite GFM tables + horizontal rules (P4-5)
- Attach InputChips with per-item remove (P4-5 attach UX)
- Silent reconnect success banner clears after 2s (P4-4)
- Mock agents hermes fields + term hostname/id/cat; hermes reply demo table (P4-1/P4-3)

## 0.1.97

- Auto-reconnect prefs + configurable max attempts (P4-4)
- MarkdownLite code line-number gutter (P4-5)
- Connect clipboard prefill / paste for pairing URI (P4-2 path without camera)
- Mock Hermes memory.search hits + tool_result fix; terminal uname/date/env (P4-1/P4-3 mock)

## 0.1.96

- MarkdownLite lightweight fenced-code token tint (P4-5 partial)
- Chat foreground resume reconnect via AppLifecycle (P4-4 partial)
- Terminal layout-driven cols/rows + Mock stty size (P4-1 protocol step)

## 0.1.95

- Sessions note and archived sort modes
- Connect deviceId sort
- Workspace children-count sort

## 0.1.94

- Sessions last-message and pinned sort modes
- Connect platform and profile id sort

## 0.1.93

- Workspace status sort
- Diff basename sort
- Agents version sort
- Activity priority sort

## 0.1.92

- Sessions sort by live
- MCP explicit name sort
- Status / Host Dashboard explicit key sort

## 0.1.91

- Agents capabilities count sort
- Sessions sort by mode / workdir / running

## 0.1.90

- Workspace dirty / branch sort
- Cron last_run sort
- Sessions sort by platform / agent

## 0.1.89

- Memory explicit time/ts sort
- Activity explicit time/ts sort
- Audit explicit time/ts sort
- Cron description sort

## 0.1.88

- Cron explicit name sort
- MCP kind sort
- Logs time (ts) sort
- Skills explicit name sort

## 0.1.87

- MCP command sort
- Activity channel sort
- Agents note sort
- Workspace explicit name sort

## 0.1.86

- Status / Host value-type sort
- Diff explicit path sort
- Agents cwd sort

## 0.1.85

- Agents provider + sessions_count sort
- MCP description sort
- Connect TLS sort
- Activity type sort

## 0.1.84

- Skills enabled sort
- Memory path sort
- Logs id sort
- Connect bridgePort sort

## 0.1.83

- MCP transport + id sort
- Agents id sort
- Cron enabled sort
- Activity level sort

## 0.1.82

- Memory id sort
- Agents project sort
- Workspace type sort
- Logs source sort

## 0.1.81

- Workspace path sort
- Skills path sort
- Cron id sort
- Activity id sort

## 0.1.80

- Status regex filter (long-press)
- Host Dashboard regex filter (long-press)
- Connect profiles regex filter (long-press)
- Diff path filter regex (long-press)

## 0.1.79

- Skills regex filter (long-press)
- Sessions regex search (long-press)
- Workspace regex filter (long-press)
- Pairing payload regex filter (long-press)

## 0.1.78

- MCP regex filter (long-press)
- Cron regex filter (long-press)
- Agents regex filter (long-press)
- Memory regex search (long-press)

## 0.1.77

- Connect profile case-sensitive filter
- Diff find case + regex (long-press)
- Audit regex filter (long-press)
- Activity regex filter (long-press)

## 0.1.76

- Sessions case-sensitive search
- Settings regex preference filter (long-press)
- Logs regex filter (long-press)
- Sessions sort by session key

## 0.1.75

- Status/Host case-sensitive capability & key filters
- Connect profile sort by note
- Agents sort by platform

## 0.1.74

- Agents case-sensitive filter
- Memory case-sensitive search
- Connect profile sort by port
- Diff sort files by deletions

## 0.1.73

- Audit case-sensitive filter
- Logs case-sensitive filter
- Workspace case-sensitive filter
- Skills case-sensitive filter

## 0.1.72

- MCP case-sensitive filter
- Activity case-sensitive filter
- Cron case-sensitive filter
- Memory sort by scope

## 0.1.71

- Pairing: sort payload lines A↔Z
- Agents: sort by status
- Skills: sort by tags + search tags
- Diff: sort files by additions

## 0.1.70

- Logs: sort by logger/source
- Memory: relative timestamps toggle
- Sessions: sort by model
- Settings: case-sensitive pref filter

## 0.1.69

- Audit: relative timestamps toggle
- Activity: relative timestamps toggle
- Chat: regex transcript search (long-press)
- Cron: sort by next_run

## 0.1.68

- Memory: sort by confidence/score
- Activity: sort by source/origin
- MCP: transport filter chips
- Diff: sort files by status

## 0.1.67

- Status / Host: relative timestamps for status values
- Workspace: hide empty directories chip
- Terminal: regex find (long-press toggle)

## 0.1.66

- Sessions: filter sessions that have local notes
- Skills: sort by id/path
- Pairing: case-sensitive payload line filter
- Connect: TLS / plain profile chips

## 0.1.65

- MCP: sort by endpoint/url/command
- Cron: sort by last_status
- Diff: case-sensitive path filter
- Agents: sort by model/provider

## 0.1.64

- Activity: sort by session key
- Audit: sort by detail
- Memory: sort by content
- Chat: case-sensitive transcript search

## 0.1.63

- Workspace: sort by mtime (name → size → mtime)
- Connect: profiles sort by host / updatedAt
- Agents: status FilterChips from Host data
- Skills: sort by description

## 0.1.62

- MCP: sort by tool count
- Status / Host Dashboard: sort keys by value
- Terminal: case-sensitive find toggle
- Logs: relative timestamps toggle

## 0.1.61

- Settings: filter preference tiles by text
- Workspace: sort by size vs name (dirs first)
- Cron: sort cycle name → schedule → kind
- Chat: role filter chips (user/assistant/system/tool)

## 0.1.60

- Skills: sort by source vs name
- Agents: sort by type vs name
- Memory: sort cycle time → title → type
- Activity: sort cycle time → kind → summary

## 0.1.59

- Logs: sort cycle time → message → level
- Audit: sort cycle time → action → level
- Cron: sort by schedule vs name
- MCP: sort by status vs name

## 0.1.58

- Host Dashboard: text filter for capability chips
- Diff: status chips filter for changed files
- Connect: A→Z / Z→A sort for profile chips
- Pairing: filter host payload lines

## 0.1.57

- Terminal: newest/oldest line order toggle
- Settings: wrap/clamp long preference subtitles
- Sessions: reverse sort direction (A→Z/Z→A, newest/oldest)
- Status: filter capability chips

## 0.1.56

- Audit: sort by action A→Z / Z→A
- Logs: sort by message A→Z / Z→A
- Connect: jump to top / end
- Settings: jump to top / end (Stateful)

## 0.1.55

- Status: filter raw keys / values
- Host Dashboard: filter raw /status keys
- Connect: wrap / clamp health text and profile labels
- Activity: sort by kind A→Z / Z→A (with time fallback)

## 0.1.54

- Status: sort keys A→Z / Z→A
- Host Dashboard: sort keys A→Z / Z→A
- Memory: sort by title A→Z / Z→A (toggle with time order)
- Chat: clamp / expand long messages

## 0.1.53

- Pairing: wrap/clamp payload and host line
- Host Dashboard: wrap/clamp status values
- Sessions: wrap/clamp title and subtitle
- Diff: files A→Z / Z→A sort

## 0.1.52

- Skills: wrap/clamp list details
- MCP: wrap/clamp list details
- Cron: wrap/clamp list details
- Workspace: wrap/clamp path/entry details

## 0.1.51

- Host Dashboard: pause/resume auto-refresh
- Status: wrap/clamp raw status values
- Connect: copy profiles CSV (no tokens)
- Agents: wrap/clamp list details

## 0.1.50

- Pairing: copy public CSV (no tokens)
- Diff: auto-refresh toggle (dashboard interval)
- Settings: copy about / version text
- Terminal: copy buffer as CSV lines

## 0.1.49

- Activity: wrap / clamp event titles
- Memory: wrap / clamp content preview
- Workspace: copy listing CSV
- Sessions: copy visible meta CSV (no tokens)

## 0.1.48

- Sessions: auto-refresh toggle (dashboard interval)
- Logs: newest / oldest sort
- Diff: copy filtered files CSV
- Chat: copy all visible messages (local transcript)

## 0.1.47

- Audit: auto-refresh toggle (dashboard interval; local re-render)
- Status: jump to top / end
- Pairing: jump to top / end
- Host Dashboard: jump to top / end

## 0.1.46

- Pairing: auto-refresh toggle (dashboard interval)
- Connect: copy fingerprint hex (no tokens)
- Sessions: jump to top / end
- Host Dashboard: copy status CSV

## 0.1.45

- Skills: auto-refresh toggle (dashboard interval)
- Cron: auto-refresh toggle (dashboard interval)
- Memory: auto-refresh toggle (dashboard interval)
- Workspace: auto-refresh toggle (dashboard interval)

## 0.1.44

- Activity: jump to top / end
- Audit: jump to top / end
- Agents: auto-refresh toggle (dashboard interval)
- MCP: auto-refresh toggle (dashboard interval)

## 0.1.43

- Agents: jump to top / end
- MCP: jump to top / end
- Skills: jump to top / end
- Cron: jump to top / end

## 0.1.42

- Activity: auto-refresh toggle (dashboard interval)
- Workspace: jump to top / end
- Status: copy CSV (redacted host meta)
- Memory: jump to top / end

## 0.1.41

- MCP: A→Z / Z→A name sort
- Cron: A→Z / Z→A name sort
- Logs: auto-refresh toggle (dashboard interval)
- Audit: wrap / clamp detail lines

## 0.1.40

- Agents: A→Z / Z→A name sort
- Skills: A→Z / Z→A name sort
- Diff: jump to top / end
- Pairing: copy public JSON (no tokens)

## 0.1.39

- Terminal: jump to top / end
- Memory: newest/oldest sort toggle
- Settings: reset console prefs to defaults (no tokens)
- Host Dashboard: copy capabilities list

## 0.1.38

- Activity: newest/oldest sort toggle
- Status: auto-refresh (dashboard interval) + pause
- Workspace: All/Dirs/Files type FilterChips
- Logs: jump to top / end

## 0.1.37

- Terminal: local display timestamps toggle
- Status: Copy JSON (tokens redacted)
- Connect: copy public profiles list (no tokens)
- Diff: +adds/-dels stats in title

## 0.1.36

- Memory: Copy CSV of filtered entries
- Diff: wrap / horizontal scroll toggle
- Workspace: copy git summary (branch + changed files)
- Host Dashboard: capability FilterChips + count title

## 0.1.35

- Agents: Copy CSV of agents/projects/platforms catalog
- MCP: Copy CSV of filtered servers
- Skills: Copy CSV of filtered skills
- Cron: Copy CSV of filtered schedules

## 0.1.34

- Activity: Copy CSV of filtered events
- Memory: type FilterChips + filtered/total title
- Settings: copy local prefs summary (no tokens)
- Status: last connect test latency tile + summary field

## 0.1.33

- Cron: filtered/total title counts
- Host logs: Copy CSV of filtered lines
- Workspace: dirs-first name sort toggle + filtered/total title
- Audit: newest/oldest sort toggle; Copy all tooltip

## 0.1.32

- Skills: source FilterChips + filtered/total title counts
- Diff: local find-in-diff (display filter; copy still full diff)
- Host Dashboard: auto-refresh badge + last-ok time chips
- Pairing: AppBar copy public summary / public URI (no tokens)

## 0.1.31

- Activity: kind FilterChips + filtered/total title counts
- Agents: section chips (agents / platforms / projects)
- MCP: status FilterChips + filtered/total title counts
- Terminal: local find-in-buffer (client-only; copy still full buffer)

## 0.1.30

- Host logs: wrap toggle + title counts (filtered/total)
- Memory: scope FilterChips + clearer search chrome
- Workspace: copy directory listing + entry count in title
- Settings/Chat: chat body font scale (0.9–1.3×, device-local)

## 0.1.29

- Audit: title counts + CSV export of filtered rows
- Pairing: pull-to-refresh
- Diff: optional line numbers
- Connect: last Test & connect latency (ms) on phase banner

## 0.1.28

- Status + Host Dashboard pull-to-refresh
- Agents / Skills / MCP: Copy all + title counts
- Diff: copy path; Terminal: clear local buffer
- Connect: copy public summary (no tokens)
- Settings: keep-screen-on preference + monospace chat bodies

## 0.1.27

- Memory: live client-side refine filter + title count; Copy all follows filter
- Cron / Activity: Copy all filtered jobs/events + title counts
- Chat: subtitle shows message count and tools-hidden hint
- Pairing: larger fingerprint (13×13), hex tag + copy, verify checklist
- Workspace: path breadcrumb chips (navigate ancestors)

## [0.1.26] - 2026-07-17

### Added
- Host logs local message/level filter (client-side)
- Terminal wrap toggle with horizontal scroll when unwrap
- Sessions menu: Copy ids (title/id/session_key/project)
- Settings haptic feedback toggle; light buzz on send/pin

## [0.1.25] - 2026-07-17

### Added
- Chat: clear local transcript view (Host history untouched; Reload to refetch)
- Sessions: search debounce (220ms)
- Connect: connection status banner (ready / degraded / testing / error / idle)
- Status: last health probe card + copy health error; summary includes health fields

## [0.1.24] - 2026-07-17

### Added
- Pull-to-refresh on Agents, Audit, Workspace, Diff
- Host Dashboard copy status summary (no token)
- Chat jump-to-top FAB alongside jump-to-latest
- Terminal local font scale (A− / A+)

## [0.1.23] - 2026-07-17

### Added
- Memory: copy entry / copy all export + pull-to-refresh
- Workspace: copy path / file content; long-press entry copies path
- Pull-to-refresh on Logs, Activity, Cron, Skills, MCP
- Chat local message timestamps (HH:mm:ss on bubbles)
- Settings: app version + privacy notes

## [0.1.22] - 2026-07-17

### Added
- Agents catalog filter/copy; fixed agent title/subtitle helpers
- Diff viewer: filter changed files + copy full diff
- Status landing: health strip, snapshot chips, copy summary (no token), open sessions/dashboard
- Chat bubbles honor Compact lists (tighter margin/padding)

## [0.1.21] - 2026-07-17

### Added
- Skills / MCP local filter + copy entry
- Cron text filter + enabled/disabled chips + long-press copy
- Workspace directory entry filter (clears on navigate)
- Host Dashboard health strip (healthy / degraded / error) with Check

## [0.1.20] - 2026-07-17

### Added
- Chat composer draft autosave per session_key (device local; cleared on send)
- Sessions Group-by-project headers + Group filter chip
- Terminal local command history (↑/↓, history sheet; device only)
- Host logs: stronger level color strips/badges, fatal/critical colors, Copy all

## [0.1.19] - 2026-07-17

### Added
- Prompt history panel: filter, copy, append/replace into composer
- Sessions swipe shortcuts (pin / archive) + overflow actions menu
- Project capability badges on session tiles; Host dashboard cap icons
- Chat quote-reply: long-press message → Quote banner → send as blockquote

## [0.1.18] - 2026-07-17

### Added
- Chat/Terminal connection status lights (connecting/live/offline)
- Device-local session recents + Sort: Recent (pins still first)
- Host activity filter + tap-to-open session (or copy ref)
- Audit log Copy JSON export (redacted entries)

## [0.1.17] - 2026-07-17

### Added
- Host health heartbeat: 30s GET /status probe while connected + Sessions health strip + manual Check
- Richer Sessions empty states (first-run guide + filter reset)
- Session metadata export to clipboard (tile / visible list menu / multi-select)
- Terminal "Copy all" for local buffer (tokens still never logged)

## [0.1.16] - 2026-07-17

### Added
- Session list sort modes: updated / title / project / created (Settings + list chip; pins still first)
- In-session host profile switcher (test-and-connect another saved profile)
- Chat search hit navigation (prev/next, N/M counter, active hit border)
- High-contrast appearance toggle in Settings (stronger outlines/surfaces)
- SessionInfo.createdAt parsing for created-time sort

## [0.1.15] - 2026-07-17

### Added
- Connection share: public pairing URI / summary (no tokens) + visual fingerprint on Pairing screen
- Sessions multi-select: bulk pin / archive-or-unarchive / delete; long-press enters selection
- Chat tool-message toggle (honors Settings default showTools)
- Chat jump-to-bottom FAB; auto-scroll only while stick-to-bottom

### Notes
- Fingerprint is human verification only — camera QR scan remains P4

## [0.1.14] - 2026-07-17

### Added
- Settings screen: text scale, compact lists, dashboard auto-refresh interval, tools default
- Session local archive (hide from default list; Archived filter chip)
- Audit log search + level chips + copy visible / long-press copy entry
- Host dashboard auto-refresh driven by settings (default 15s)

## [0.1.13] - 2026-07-17

### Added
- Session rename via `PATCH /sessions/{id}` (title/name) + UI
- Message long-press copy to clipboard
- Theme toggle (system / light / dark, device local)
- Host logs readonly screen (`GET /logs`, capability `logs_readonly`)
- Mock Host log ring buffer + rename activity/log events

## [0.1.12] - 2026-07-17

### Added
- Agents catalog screen (`GET /agents` + projects summary)
- Device-local session notes (long-press / note icon; never uploaded)
- Session list filter chips: All / Pinned / Running
- Chat slash-command palette (fills input)
- MarkdownLite code fences: language label + copy button
- Mock `/agents` returns structured agent objects

## [0.1.11] - 2026-07-17

### Added
- Bridge reconnect UX: countdown hint, status chip tap, manual Reconnect
- In-chat transcript search with amber highlight on hits
- Export transcript to clipboard (Markdown + plain)
- Attachment demo chips with text preview sheet
- Host activity feed (`GET /activity`) + Activity screen + menu/dashboard links

### Protocol
- management-subset: `/activity?limit=`
- status capability: `activity_readonly`
- Mock activity ring buffer on host.start / session.create / chat.message

## [0.1.10] - 2026-07-17

### Added
- MarkdownLite chat bubbles (headings/lists/code/bold; no extra pub package)
- Host memory browser (`GET /memory`) + Cron schedules (`GET /cron`) readonly
- Git diff viewer (`GET /workspace/diff`) with green/red unified coloring
- Session pin/favorite (device-local SharedPreferences)
- Dashboard + Sessions menu shortcuts for memory/cron/diff
- Mock markdown-rich agent replies for UI verification

### Protocol
- management-subset: `/memory`, `/cron`, `/workspace/diff`
- status capabilities: `memory_readonly`, `cron_readonly`, `diff_readonly`

## [0.1.9] - 2026-07-17

### Added
- Host status dashboard (refreshable `/status`, capability chips, shortcuts)
- Readonly workspace browser (`GET /workspace`, `/workspace/git`) + Mock tree
- Chat local prompt history + favorites (device SharedPreferences only)
- Terminal quick-action chips: help/pwd/ls/whoami/y/n/^C/clear
- Status payload: `sessions_count`, `active_runs`, `capabilities[]`

### Notes
- Inspired by common remote-console UX patterns; **in-repo only**, no third-party runtime
- Workspace is readonly demo — Host remains source of truth

## [0.1.8] - 2026-07-17

### Added
- Lightweight Bridge terminal channel (`terminal_input` / `terminal_out`) + App Terminal screen
- MCP readonly catalog (`GET /mcp`) + MCP screen
- Connect: import `huanhermes://connect?...` pairing URI (tokens optional; never wipe existing)
- Sessions local search filter
- Protocol docs for terminal + MCP endpoints

### Notes
- Terminal is protocol demo / Mock echo — not a full remote PTY
- Product remains HuanHermes-owned Host protocol only


## [0.1.7] - 2026-07-17

### Changed
- Product framing: HuanHermes **owns** Bridge/Mgmt protocol; Mock/self-host are first-class
- Docs/comments no longer present third-party hosts as install/runtime dependency
- Session paths described as flat vs project-scoped (not external product dialects)

### Notes
- Behavior unchanged: dual-path Mgmt + Mock still work; only wording/ownership clarified


## [0.1.6] - 2026-07-17

### Added
- Hermes Mock session flavor (memory.search tool, hermes project)
- Capability-gated chat toolbar (mode/model/dir/stop/tools)
- Attachments protocol path + in-app attach demo
- Skills readonly screen + GET /skills on Mock
- Pairing screen + GET /pairing (token-free URI)
- Release checklist + self-host compatibility guide

### Notes
- Live Host / channels untouched; App remains console-only


## [0.1.5] - 2026-07-17

### Added
- ADR-002 Hermes adapter (App stays console; Host-side hermes agent_type + capabilities)
- Multi-server connection profiles (secure per-profile tokens, migrate v1 → v2)
- Connect UI: profile chips, new/delete profile, TLS plaintext warning
- `Security.redactText` helpers; Mock project `capabilities` fields

### Notes
- Does not modify any live Host / channel config
- Real Hermes process still Host-side (P2-2+)


## [0.1.4] - 2026-07-17

### Added
- Management dual-dialect client: flat `/sessions` (Mock) + project-scoped `/projects/{}/sessions` (project-scoped)
- Mock Host mirrors both path shapes + `/agents`, project session detail
- `docs/guides/connect-real-host.md` — user connects App to their Host without editing Host channels
- Bridge handling for `preview_start` / `card` / `update_message` (protocol reference)

### Notes
- External projects are design references only; this repo does not modify production Host configs
- App still does not run coding agent loops locally


## [0.1.3] - 2026-07-17

### Added
- Console controls: mode / model / dir / stop toolbar
- Bridge `cancel` + Mock cancellable streaming runs (`run_done`, thinking, tool_*)
- Session transcript reload via `GET /api/v1/sessions/{id}`
- Auto-reconnect with backoff; local redacted audit log screen
- Empty states for sessions/chat; running indicator
- `docs/roadmap-console-parity.md` capability matrix

### Notes
- P1-2 real Host connect path via App tokens + dual-path client
- App remains a remote console — agent loop stays on server


## [0.1.2] - 2026-07-17

### Added
- P0-8 Sessions screen: list / create / delete via Management API
- P0-8 Chat screen: Bridge WS connect, streaming transcript, send message
- P0-9 Flutter `TranscriptReducer` (stream collapse + permission events)
- P0-10 Permission buttons UI (`allow` / `deny` / `allow_all` → `card_action`)
- Dart `BridgeClient` + expanded `MgmtClient` (sessions CRUD)
- Unit tests for transcript reducer and session create


## [0.1.1] - 2026-07-17

### Added
- Flutter Android app scaffold under `apps/mobile` (`com.huanmeng.huanhermes`)
- P0-7 Connect screen: host/ports/TLS/tokens
- Secure token storage (`flutter_secure_storage`) + public prefs (`shared_preferences`)
- Management client + typed errors; connection test via `GET /api/v1/status`
- Unit tests for connection config / mgmt client / controller


## [0.1.0] - 2026-07-17

### Added
- Repository scaffold (docs, protocol package, mock host, example configs)
- ADR-001 architecture decision (HuanHermes Host protocol + console UI)
- Bridge / Management protocol subset documentation
- Python mock Bridge + Management host for offline UI development
- Python reference Bridge client + unit tests
- Master agent prompt and task board (P0–P3)
