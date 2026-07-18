# Changelog

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
