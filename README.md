# Codex Tools

Native swift macOS menu bar app for managing multiple Codex auth sessions.

<img width="388" height="416" alt="image" src="https://github.com/user-attachments/assets/d5429823-9a61-4dd3-a3e6-63d5c8231385" />


## Features

- Menu bar switching for active accounts
- Manage window for add/import/rename/delete
- Usage refresh and "next best" recommendation
- Switch guardrails when Codex processes are running
- Optional "Close Codex" process termination

## Requirements

- macOS 14+
- Swift 6 (or compatible Xcode)

## Run

```bash
git clone <your-repo-url>
cd codex-tools
swift run CodexTools
```

Or open `CodexTools.xcodeproj` and run the `CodexTools` target.

## Install (Homebrew)

```bash
brew tap VincentBurke/tap
brew install codex-tools
```

Start at login (recommended):

```bash
brew services start codex-tools
```

Stop background launch-at-login behavior:

```bash
brew services stop codex-tools
```

Start once for the current session (no launchd service management):

```bash
codex-tools
```

### Quit Behavior When Started Via `brew services`

- Choosing `Quit codex-tools` from the menu should exit the app and keep it stopped for the current login session.
- If the process crashes, launchd should restart it automatically.
- To disable launch-at-login entirely, run `brew services stop codex-tools`.

## Configuration

- `CODEX_HOME` (default: `~/.codex`)
- `CODEX_TOOLS_HOME` (default: `~/.codex-tools`)
- Active auth file: `${CODEX_HOME}/auth.json`
- Account store: `${CODEX_TOOLS_HOME}/accounts.json`
Stored auth files are written with restrictive file permissions (`0600`).

## Development

```bash
swift test
```

This project treats warnings as errors in SwiftPM targets.

## Release

Push a `v*` tag to build release archives, create/update a GitHub release, and update the Homebrew formula in `VincentBurke/homebrew-tap`.

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

For release prerequisites and troubleshooting, see `docs/releasing.md`.

## Project Layout

- `CodexTools/` app target (menu bar UI, AppKit + SwiftUI)
- `CodexToolsCore/` domain/runtime/services
- `CodexToolsTests/` unit and integration-style tests
- `CodexToolsUITests/` UI test target scaffold
- `Package.swift` SwiftPM entrypoint

## Current Limits

- `auth.json` imports require token-based auth data (API-key-only imports are rejected).
- Usage data for API-key accounts is reported as unavailable.
