# AI Usage

English | [简体中文](./README.zh-CN.md)

A lightweight, native macOS menu bar app for viewing the remaining quota,
usage windows, or account balance of AI coding services.

Codex is enabled by default. Additional providers can be enabled from Settings,
and the menu bar always shows a compact summary for the first enabled provider.

> [!IMPORTANT]
> AI Usage is an independent, unofficial community project. It is not affiliated
> with, endorsed by, or sponsored by any provider listed below.

## Features

- Native SwiftUI menu bar experience for macOS 13 and later
- Compact always-visible usage summary with detailed expandable rows
- Automatic discovery of locally installed Codex, Claude Code, and Kimi Code
- Credentials for API-based providers stored in the macOS Keychain
- Provider-specific refresh intervals to avoid unnecessary polling
- Optional launch at login
- Universal build for Apple Silicon and Intel Macs
- No project-operated proxy, analytics service, or telemetry backend

## Provider support

| Provider | Status | Configuration | Information shown |
| --- | --- | --- | --- |
| Codex | Available, default | Automatically discovers the local Codex CLI | Remaining percentage, usage windows, and reset times |
| Claude Code | Available | Automatically discovers Claude Code and installs an owned status-line collector | Available usage windows and reset times |
| Kimi Code | Available, best effort | Automatically discovers Kimi Code and reads its local login session | Subscription quota windows |
| MiniMax | Available, best effort | Token Plan subscription key | Remaining percentage and reset windows |
| DeepSeek | Available | DeepSeek API key | API account balance |
| Qoder Teams | Available | Teams API key, organization ID, and member ID | Plan, resource package, shared, and total quota |
| GLM Coding Plan | Not yet selectable | None | Reserved until a stable usage-query integration is available |

Provider APIs and local CLI formats can change without notice. “Available”
means the integration is implemented in this project; it is not a guarantee of
permanent upstream compatibility.

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
- **Kimi Code:** the app locates the `kimi` executable and reads the Kimi Code
  login session stored on the Mac.
- **MiniMax, DeepSeek, and Qoder:** secret keys are stored in the macOS
  Keychain. Non-secret provider settings are stored in the app's local
  preferences.
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

## Development approach: vibecoding

This is openly disclosed as a **vibecoding project**. The product direction,
interaction decisions, reviews, and release acceptance are led by the human
maintainer, while a substantial portion of the implementation and
documentation is drafted and iterated with AI coding agents, primarily Codex.

AI-assisted development does not guarantee correctness. Automated tests,
manual review, and real-device verification are used where practical, but
contributors and users should still review security-sensitive behavior and
report issues.

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
