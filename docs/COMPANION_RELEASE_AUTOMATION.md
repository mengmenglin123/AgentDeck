# Companion Release Automation

The private App repository publishes verified Host Companion archives to the
public `mengmenglin123/huanhermes-companion` repository without storing a
personal GitHub token in Actions.

## Flow

1. The main build workflow completes Flutter, protocol, Host, and APK gates.
2. `publish-companion` derives the Companion version from `pubspec.yaml`.
3. It verifies the matching bundled archive exists and scans it for private-key
   and GitHub-token patterns.
4. A repository-scoped write Deploy Key syncs the archive and `SHA256SUMS` to
   the public repository.
5. A new immutable version tag triggers the public repository workflow.
6. The public workflow verifies SHA-256 and creates the GitHub Release.

Existing version contents cannot be replaced. If the archive changes, bump the
App/Companion version before merging. The public workflow uses its own scoped
`GITHUB_TOKEN`; the private workflow receives only the dedicated Deploy Key in
`COMPANION_DEPLOY_KEY`.
