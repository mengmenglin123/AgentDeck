# Changelog

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
