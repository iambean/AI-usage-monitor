# AI Usage

English | [简体中文](./README.zh-CN.md)

A lightweight, native macOS menu bar app for viewing the remaining quota,
usage windows, or account balance of AI coding services.

Codex is enabled by default. Additional providers can be enabled from Settings,
and the menu bar always shows a compact summary for the first enabled provider.

> [!NOTE]
> **AI Usage is macOS only.** It supports macOS 13 and later on Apple Silicon
> and Intel Macs. Windows support is not currently planned.

> [!IMPORTANT]
> AI Usage is an independent, unofficial community project. It is not affiliated
> with, endorsed by, or sponsored by any provider listed below.

## Features

- Native SwiftUI menu bar experience for macOS 13 and later
- Compact always-visible usage summary with detailed expandable rows
- Five-hour quota is preferred in the menu bar; the panel shows each usage window and its exact reset time
- The main panel and Settings follow the normal macOS window stacking behavior
- Simplified Chinese and English UI, with Chinese as the default fallback
- Automatic discovery of locally installed Codex, Claude Code, and Kimi Code
- Credentials for API-based providers stored in the macOS Keychain
- Primary-provider polling with hourly secondary refreshes and immediate refresh when the panel opens
- Automatic polling reduction when macOS Low Power Mode is active
- Clear unavailable states and recovery suggestions instead of stale cached values after an error
- Local, redacted diagnostics export with no third-party telemetry
- Lightweight GitHub Releases update check, limited to once per day in the background
- Optional launch at login
- Universal build for Apple Silicon and Intel Macs
- No project-operated proxy, analytics service, or telemetry backend

## Provider support

| Provider | Status | Configuration | Information shown |
| --- | --- | --- | --- |
| Codex | Available, default | Automatically discovers the local Codex CLI | Remaining percentage, usage windows, and reset times |
| Claude Code | Available | Automatically discovers Claude Code and installs an owned status-line collector | Available usage windows and reset times |
| Cursor | Teams available; Personal is web-only | Teams admin API key with an inline Teams/Personal switch | Team spend and member count for the current cycle; official Usage page for Personal |
| Kimi Code | Available, best effort | Automatically discovers Kimi Code and reads its local login session | Subscription quota windows |
| MiniMax | Available, best effort | Token Plan subscription key | Remaining percentage and reset windows |
| DeepSeek | Available | DeepSeek API key | API account balance |
| Qoder Teams | Available | Teams API key, organization ID, and member ID | Plan, resource package, shared, and total quota |
| GLM Coding Plan | Not yet selectable | None | Reserved until a stable usage-query integration is available |

Provider APIs and local CLI formats can change without notice. “Available”
means the integration is implemented in this project; it is not a guarantee of
permanent upstream compatibility.

## Resource and reliability

- Keep the primary menu bar provider current; refresh secondary providers less
  often in the background and refresh all providers when the panel opens.
- Reduce background polling automatically when macOS Low Power Mode is active,
  while preserving manual refresh.
- Treat 35 MB for the idle app and 50 MB including the Codex App Server as
  resource budgets. Investigate only after three consecutive measurements
  exceed a budget.
- Keep one Codex App Server process while Codex is enabled, with cleanup,
  duplicate-process prevention, and backoff after unexpected exits.
- Never present stale cached values as a successful refresh. Show a clear
  unavailable state and a provider-specific recovery suggestion instead.
- Prefer official APIs; integrations that depend on local CLI sessions are
  labeled accordingly, while unverified integrations remain unavailable.
- Remain telemetry-free. Diagnostics are local, redacted, and exported only
  when the user explicitly requests them.
- Distribute public builds through signed and notarized GitHub Releases, with
  a lightweight version check rather than a background auto-update framework.

## Installation

### Download a release

Download the latest DMG or ZIP from
[GitHub Releases](https://github.com/iambean/codex-usage-monitor/releases) when
a release artifact is available.

Public release builds should be signed with a Developer ID certificate and
notarized by Apple. Locally built ad-hoc packages may trigger a macOS Gatekeeper
warning.

### Build from source

Requirements:

- macOS 13 or later
- Xcode Command Line Tools or Xcode
- Swift 5.10 or later

```bash
git clone https://github.com/iambean/codex-usage-monitor.git
cd codex-usage-monitor
swift test
./scripts/build-app.sh
open "dist/AI Usage.app"
```

Create universal DMG and ZIP packages:

```bash
./scripts/package-release.sh
```

The packaging script uses ad-hoc signing by default. For distribution, provide
a Developer ID identity and notarization profile:

```bash
AI_USAGE_SIGNING_IDENTITY="Developer ID Application: ..." \
  ./scripts/package-release.sh

AI_USAGE_NOTARY_PROFILE="notary-profile" \
  ./scripts/notarize-release.sh "dist/AI-Usage-<version>-universal.dmg"
```

## Configuration and local changes

- **Codex:** the app locates the `codex` executable and communicates with its
  local App Server process.
- **Claude Code:** enabling the provider may add an AI Usage-owned
  `statusLine` command to `~/.claude/settings.json`. Existing unrelated
  `statusLine` configurations are not overwritten. Disabling the provider
  removes only the configuration owned by AI Usage.
- **Kimi Code:** the app locates the `kimi` executable, reads the Kimi Code
  login session stored on the Mac, and refreshes its short-lived access token
  when necessary.
- **Cursor:** Teams is the default mode. Its admin API key is stored in the
  macOS Keychain and the official team usage API is polled conservatively.
  Personal mode does not use undocumented APIs and only opens the official
  Usage page.
- **MiniMax:** choose automatic, Global, or Mainland China service-region
  detection. The Token Plan key is stored in the macOS Keychain.
- **DeepSeek and Qoder:** secret keys are stored in the macOS Keychain.
  Non-secret provider settings are stored in the app's local preferences.
- **Launch at login:** managed through the macOS Service Management framework.

## Privacy and security

- AI Usage does not operate an intermediary server.
- Provider requests are sent directly from the Mac to the corresponding
  provider.
- API keys are stored in the macOS Keychain and are not written to this
  repository.
- Codex, Claude Code, and Kimi Code integrations read only the local state
  required for usage collection.
- The app does not include its own analytics or telemetry service.

Each provider still processes requests under its own privacy policy and terms.
Review the provider's policies before enabling an integration.

## Contributing

Issues and pull requests are welcome. Please:

1. Describe the provider, expected behavior, and observed behavior.
2. Never include API keys, access tokens, account identifiers, or raw private
   responses in an issue.
3. Add or update tests when changing parsers or provider integrations.
4. Run `swift test` before submitting a pull request.
5. Keep provider polling conservative and compatible with upstream guidance.

By submitting a contribution, you agree that it may be distributed under the
project's MIT License.

## Third-party resources and trademarks

This repository does not use third-party Swift Package dependencies. It does
use Apple system frameworks and system-provided SF Symbols, and it includes
provider brand marks solely to identify integrations.

Provider names, product names, trademarks, and logos belong to their respective
owners and are **not** granted under the MIT License. See
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for the complete attribution
and licensing boundary.

## License

The source code and original project assets are available under the
[MIT License](./LICENSE).

The MIT License does not grant rights to third-party trademarks, service marks,
logos, or other brand assets. See
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).
