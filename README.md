# Codex Tools (Native Swift)

This folder contains the hard-cutover macOS-native Swift implementation.

## Build
```bash
cd /Users/vincent/projects/codex-tools
swift build
```

## Test
```bash
cd /Users/vincent/projects/codex-tools
swift test
```

## Run
```bash
cd /Users/vincent/projects/codex-tools
swift run CodexTools
```

## Project Layout
- `CodexTools/` app target (menu bar shell, AppKit + SwiftUI)
- `CodexToolsCore/` core domain/runtime/services
- `CodexToolsTests/` parity test suite
- `CodexToolsUITests/` UI test target scaffold
- `docs/` migration artifacts and cutover checklists
