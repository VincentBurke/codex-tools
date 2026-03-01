# Swift Hard Cutover Checklist

## Preconditions
1. Swift package builds cleanly with warnings as errors.
2. Swift tests pass.
3. Parity matrix reviewed and accepted.
4. Runtime loop cadence (`0.20s`) and strict process discovery behavior accepted.

## Build and Test Commands
```bash
cd /Users/vincent/projects/codex-tools
swift build
swift test
```

## Runtime Validation
1. Launch app from Swift package executable:
```bash
cd /Users/vincent/projects/codex-tools
swift run CodexTools
```
2. Validate status item appears as `CS` in menu bar.
3. Open popover, confirm all footer actions render.

## Functional Validation
1. Import account from `auth.json` and verify:
- Account appears in manage window.
- `accounts.json` updated in `~/.codex-tools/`.
2. OAuth add flow:
- Browser opens to OpenAI auth.
- Callback success page renders.
- Account becomes active.
3. Switch account:
- `~/.codex/auth.json` contents update with selected credentials.
- `last_used_at` updates in store.
4. Rename account:
- Empty rename rejected.
- Duplicate rename rejected.
5. Delete account:
- Confirmation required.
- Active fallback reassigned to first remaining.
6. Refresh usage:
- Refresh all updates percentage fields.
- Stale indicators appear when expected.
7. Process gating:
- Running `codex` process blocks switching for inactive targets.
- `Close Codex` terminates process tree.
- Process discovery command failures are surfaced explicitly (no silent fallback).

## File Contract Validation
1. `~/.codex-tools/accounts.json`
- `version == 2`
- `auth_mode` and `auth_data.type` serialized as snake_case.
- `usage_cache` entries include `cached_at_unix`.
2. `~/.codex-tools/ui.json`
- `sidebar_mode` matches selected mode.
3. `~/.codex/auth.json`
- API key mode writes `OPENAI_API_KEY` only.
- ChatGPT mode writes `tokens` and `last_refresh`.
4. Permissions
- Sensitive files written as `0600`.

## Repository Cutover
1. Swift implementation is now the primary execution path.
2. Root documentation updated to point to Swift package commands.
3. Legacy Rust implementation retained only as reference until explicit removal.

## Sign-off Criteria
1. `swift build` passes.
2. `swift test` passes.
3. Manual QA checklist passes for add/switch/rename/delete/refresh/process gating.
4. JSON schema parity confirmed from produced files.
