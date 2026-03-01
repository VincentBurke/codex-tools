# Swift Simplification + Best-Practice Audit (Production, High/Medium)

## Scope
- Included: production Swift sources under:
  - `CodexTools/Sources/CodexTools`
  - `CodexToolsCore/Sources/CodexToolsCore`
- Excluded: test targets (`CodexToolsTests`, `CodexToolsUITests`) except as behavior reference.
- Severity filter: High + Medium only.
- Rubric:
  - Unnecessary complexity / redundant logic
  - Silent fallbacks / error suppression
  - Avoidable performance overhead
  - Non-idiomatic Swift patterns

## Baseline
- `swift test` (run on 2026-02-28) passed: 29 tests, 0 failures.

## Production File Coverage Checklist
- [x] `CodexTools/Sources/CodexTools/A11yID.swift`
- [x] `CodexTools/Sources/CodexTools/AddAccountSheetView.swift`
- [x] `CodexTools/Sources/CodexTools/AppController.swift`
- [x] `CodexTools/Sources/CodexTools/AppDelegate.swift`
- [x] `CodexTools/Sources/CodexTools/CodexToolsApp.swift`
- [x] `CodexTools/Sources/CodexTools/ManageAccountsView.swift`
- [x] `CodexTools/Sources/CodexTools/ManageWindowController.swift`
- [x] `CodexTools/Sources/CodexTools/StatusPopoverView.swift`
- [x] `CodexTools/Sources/CodexTools/UIFormatting.swift`
- [x] `CodexTools/Sources/CodexTools/UITheme.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/Auth.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/CodexJSON.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/Models.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/OAuth.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/Paths.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/ProcessService.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/Protocols.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/Runtime.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/RuntimeModels.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/Storage.swift`
- [x] `CodexToolsCore/Sources/CodexToolsCore/Usage.swift`

## Findings (Ordered by Severity then Risk)

### 1) High — Process check always reports change, causing unnecessary snapshot churn
- **Evidence:** `CodexToolsCore/Sources/CodexToolsCore/Runtime.swift:323`, `CodexToolsCore/Sources/CodexToolsCore/Runtime.swift:94`
- **Why over-complex / non-idiomatic:** `checkProcessesBackground()` always returns `true`, so `tick()` marks snapshots changed every process-check cycle even when process state is unchanged.
- **Root cause:** Change detection is hard-coded instead of comparing previous/new process state.
- **Minimal simplification patch shape:** Make `checkProcessesBackground()` return `true` only when `state.processInfo` actually changes (`old != new`); return `false` on no-op.
- **Behavioral guardrails:** Keep process polling cadence and error surfacing unchanged; only reduce no-op publishes.

### 2) High — Silent failure in process detection via `try?` produces partial/empty results
- **Evidence:** `CodexToolsCore/Sources/CodexToolsCore/ProcessService.swift:37`, `CodexToolsCore/Sources/CodexToolsCore/ProcessService.swift:46`
- **Why over-complex / non-idiomatic:** Failures from `pgrep`/`ps` are swallowed, violating fail-loud error handling and making process state unreliable.
- **Root cause:** `try?` around command execution with no error propagation path.
- **Minimal simplification patch shape:** Convert `findCodexProcesses()` to `throws`; propagate command failures into `checkCodexProcesses()` and surface them through existing runtime error pipeline.
- **Behavioral guardrails:** Preserve detection semantics and switch-block logic when commands succeed; only change failure behavior from silent fallback to explicit error.

### 3) Medium — Redundant `refreshAllUserInitiated` branch/state with identical behavior
- **Evidence:** `CodexToolsCore/Sources/CodexToolsCore/Runtime.swift:404`, `CodexToolsCore/Sources/CodexToolsCore/Runtime.swift:443`
- **Why over-complex / non-idiomatic:** Branches execute identical code in both paths (`setError(...)`), and the extra state does not change outcomes.
- **Root cause:** Partially implemented differentiation between user-initiated/background refresh error behavior.
- **Minimal simplification patch shape:** Remove `refreshAllUserInitiated` state and conditional branch; keep one error path in `completeRefreshAll`.
- **Behavioral guardrails:** Preserve current visible behavior (errors still surfaced).

### 4) Medium — Over-frequent hot polling loop relative to runtime intervals
- **Evidence:** `CodexTools/Sources/CodexTools/AppController.swift:123`
- **Why over-complex / non-idiomatic:** 20Hz timer (`0.05s`) drives many empty ticks while runtime work is gated at 1s/3s/30s+ intervals.
- **Root cause:** Fixed high-frequency timer not aligned to minimum useful interval.
- **Minimal simplification patch shape:** Increase timer interval to a coarser value (for example 0.2s–0.5s) or schedule next wakeup based on nearest runtime deadline.
- **Behavioral guardrails:** OAuth completion responsiveness must remain acceptable; no regressions in keyboard/UI command handling.

### 5) Medium — Row-level “Refresh Usage” action calls global refresh
- **Evidence:** `CodexTools/Sources/CodexTools/ManageAccountsView.swift:229`, `CodexTools/Sources/CodexTools/ManageAccountsView.swift:706`
- **Why over-complex / non-idiomatic:** UI wording and action scope are mismatched, increasing cognitive load and surprising behavior.
- **Root cause:** Per-account context menu action dispatches `.refreshAll`.
- **Minimal simplification patch shape:** Hard-cutover one of:
  - Rename menu item to “Refresh All Usage”, or
  - Add a targeted single-account refresh command path and call that from row context.
- **Behavioral guardrails:** Keep existing global refresh button behavior untouched.

### 6) Medium — Repeated formatter allocations in frequently called paths
- **Evidence:** `CodexToolsCore/Sources/CodexToolsCore/Runtime.swift:658`, `CodexToolsCore/Sources/CodexToolsCore/CodexJSON.swift:35`
- **Why over-complex / non-idiomatic:** Date formatter construction is expensive and repeated per call.
- **Root cause:** New `DateFormatter` / `ISO8601DateFormatter` instances created each invocation.
- **Minimal simplification patch shape:** Replace per-call formatter creation with cached static formatters (or a small formatter factory with shared instances).
- **Behavioral guardrails:** Preserve exact date string formats required by current JSON parity constraints.

### 7) Medium — OAuth form-body encoding silently falls back to unencoded values
- **Evidence:** `CodexToolsCore/Sources/CodexToolsCore/OAuth.swift:480`
- **Why over-complex / non-idiomatic:** `?? original` on percent-encoding hides encoding failures and risks malformed token exchange payloads.
- **Root cause:** Manual string concatenation with per-field fallback.
- **Minimal simplification patch shape:** Build form body using strict encoding (URL components/query item serialization or explicit helper that throws on encode failure).
- **Behavioral guardrails:** Keep request fields and endpoint unchanged; only tighten failure behavior.

### 8) Medium — Dead/duplicated keyboard orchestration path
- **Evidence:** `CodexTools/Sources/CodexTools/AppController.swift:90`, `CodexTools/Sources/CodexTools/ManageAccountsView.swift:581`
- **Why over-complex / non-idiomatic:** Keyboard command resolution exists in both controller and view; controller path is currently unused.
- **Root cause:** Refactor left stale orchestration method in controller.
- **Minimal simplification patch shape:** Delete `AppController.handleManageKeyboardCommand(...)` and keep single keyboard flow in view (or invert ownership, but choose one).
- **Behavioral guardrails:** Preserve current keyboard behavior already covered by UI-focused tests.

### 9) Medium — Full sorting used where max selection is sufficient
- **Evidence:** `CodexTools/Sources/CodexTools/UIFormatting.swift:309`
- **Why over-complex / non-idiomatic:** `sorted(...).first` performs more work than needed and obscures intent.
- **Root cause:** Ranking implementation optimized for convenience over minimal work.
- **Minimal simplification patch shape:** Replace full sort with single-pass selection (`max(by:)`) for weekly and five-hour candidates.
- **Behavioral guardrails:** Maintain exact ranking tie-break semantics from current tests.

### 10) Medium — O(n²) dedupe in process scan
- **Evidence:** `CodexToolsCore/Sources/CodexToolsCore/ProcessService.swift:62`
- **Why over-complex / non-idiomatic:** Repeated `pids.contains(pid)` inside loops scales poorly and is avoidable.
- **Root cause:** Array-based dedupe instead of set-backed membership checks.
- **Minimal simplification patch shape:** Use `Set<Int32>` for collection/dedupe, then convert to stable array output as needed.
- **Behavioral guardrails:** Preserve current PID inclusion/exclusion rules and ordering expectations (if any).

### 11) Medium — Runtime state fields updated but not consumed
- **Evidence:** `CodexToolsCore/Sources/CodexToolsCore/RuntimeModels.swift:18`, `CodexToolsCore/Sources/CodexToolsCore/RuntimeModels.swift:19`, `CodexToolsCore/Sources/CodexToolsCore/RuntimeModels.swift:21`, `CodexToolsCore/Sources/CodexToolsCore/Runtime.swift:202`
- **Why over-complex / non-idiomatic:** `loading`, `error`, and `switchingID` in `AppState` are set but not represented in snapshots or UI behavior, creating dead state and mental overhead.
- **Root cause:** Partial state-modeling from earlier iterations without end-to-end wiring.
- **Minimal simplification patch shape:** Remove unused state members and writes, or wire them fully into snapshots/UI; prefer removal.
- **Behavioral guardrails:** Keep current surfaced error path (`pendingErrorForUI`) and visible UI behavior unchanged unless explicitly expanded.

## Follow-up Test Scenarios for Remediation Phase
1. Snapshot publication only on process-state change.
2. `refreshAllUserInitiated` removal preserves current error surfacing.
3. Process-detection command failures become explicit runtime errors.
4. Poll cadence change does not regress OAuth responsiveness.
5. Row context refresh semantics match label semantics.
6. Formatter caching preserves `accounts.json` and `auth.json` parity.
7. Recommendation ranking refactor preserves existing tie-break behavior.
