# Codex Tools

Native swift macOS menu bar app for managing multiple Codex auth sessions.

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

## Project Layout

- `CodexTools/` app target (menu bar UI, AppKit + SwiftUI)
- `CodexToolsCore/` domain/runtime/services
- `CodexToolsTests/` unit and integration-style tests
- `CodexToolsUITests/` UI test target scaffold
- `Package.swift` SwiftPM entrypoint

## Current Limits

- `auth.json` imports require token-based auth data (API-key-only imports are rejected).
- Usage data for API-key accounts is reported as unavailable.
