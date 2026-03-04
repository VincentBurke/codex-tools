# Codex-Tools

Lightweight, native Swift macOS menu bar app for switching between multiple Codex auth sessions.

<img width="388" height="416" alt="Codex Tools screenshot" src="https://github.com/user-attachments/assets/d5429823-9a61-4dd3-a3e6-63d5c8231385" />

## Features

- Fast menu bar account switching
- Manage accounts (add/import/rename/delete)
- Usage refresh with "next best" recommendation
- Switch guardrails while Codex processes are running
- Force Kill Codex

## Install

### Homebrew

```bash
brew tap VincentBurke/tap
brew install codex-tools
```

Run once:

```bash
codex-tools
```

Start at login (recommended):

```bash
brew services start codex-tools
```

Disable launch-at-login:

```bash
brew services stop codex-tools
```

When started via `brew services`:

- `Quit codex-tools` exits the app and keeps it stopped for the current session.
- If the process crashes, launchd restarts it.

## Run From Source

```bash
git clone <your-repo-url>
cd codex-tools
swift run CodexTools
```

Or open `CodexTools.xcodeproj` and run the `CodexTools` target.

## Configuration

- `CODEX_HOME` (default: `~/.codex`)
- `CODEX_TOOLS_HOME` (default: `~/.codex-tools`)
- Active auth file: `${CODEX_HOME}/auth.json`
- Account store: `${CODEX_TOOLS_HOME}/accounts.json`
- Stored auth files use restrictive permissions (`0600`)

## Development

```bash
swift test
```

## Current Limits

- `auth.json` imports require token-based auth data (API-key-only imports are rejected)
- API-key accounts report usage as unavailable
