# Changelog

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
