# Changelog

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
- Does not modify any live Host / cc-connect / channel config
- Real Hermes process still Host-side (P2-2+)


## [0.1.4] - 2026-07-17

### Added
- Management dual-dialect client: flat `/sessions` (Mock) + project-scoped `/projects/{}/sessions` (cc-connect shape)
- Mock Host mirrors both path shapes + `/agents`, project session detail
- `docs/guides/connect-real-host.md` — user connects App to their Host without editing Host channels
- Bridge handling for `preview_start` / `card` / `update_message` (protocol reference)

### Notes
- LiveAgent & cc-connect remain **references only**; no production Host config is modified by this repo
- App still does not run coding agent loops locally


## [0.1.3] - 2026-07-17

### Added
- LiveAgent-oriented console controls: mode / model / dir / stop toolbar
- Bridge `cancel` + Mock cancellable streaming runs (`run_done`, thinking, tool_*)
- Session transcript reload via `GET /api/v1/sessions/{id}`
- Auto-reconnect with backoff; local redacted audit log screen
- Empty states for sessions/chat; running indicator
- `docs/roadmap-liveagent-parity.md` capability matrix

### Notes
- P1-2 true cc-connect wiring still open (deploy/docs next)
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
- ADR-001 architecture decision (cc-connect-compatible host + LiveAgent-inspired UI)
- Bridge / Management protocol subset documentation
- Python mock Bridge + Management host for offline UI development
- Python reference Bridge client + unit tests
- Master agent prompt and task board (P0–P3)
