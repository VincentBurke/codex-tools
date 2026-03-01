# Codex Tools Swift UI Spec

## Design Goals
1. Keep all existing Rust functionality and workflows intact.
2. Modernize visuals to a compact native macOS style.
3. Preserve operational clarity for high-frequency account switching.

## Surface 1: Status Menu Popover
### Container
- Width: `420pt`
- Dynamic height with scrollable account section.
- Lightweight section spacing and dense action rows.

### Header
- Primary action button:
- `Refresh All`
- `Refreshing usage...` while active
- Disabled while refresh is in-flight.

### Account Rows
- One row per account sorted by weekly remaining descending.
- For accounts at `<= 3%` weekly remaining, order by soonest weekly reset first.
- Accounts in that low-weekly group with unknown reset time appear after known reset times.
- Prefix markers:
- Active: `●`
- Inactive: `○`
- Inline health indicators:
- Normal: `5h XX% · Weekly YY%`
- Stale: suffix `(stale)`
- Error/unavailable: `5h -- · Weekly --`
- Row disabled when account is active or switching is blocked by running Codex processes.

### Footer Actions
- `Manage Accounts...`
- `Close Codex` (disabled when `process_count == 0`)
- `Quit codex-tools`

## Surface 2: Manage Accounts Window
### Window
- Size: `760x470`
- Fixed min/max to match parity behavior.
- Floating utility-style window.

### Top Controls
- `Add Account...` button
- Segmented control:
- `Compact`
- `Detailed`
- Selection persisted to `ui.json` as `sidebar_mode`.

### Sidebar (Left, 300pt)
- Scrollable account cards.
- Card fields:
- Avatar initial
- Account name
- Weekly reset countdown
- 5h and Weekly progress bars with percentages
- Status line: `Stale`, `Usage unavailable`, or combined.
- Footer action: `Add Account...`.

### Details Pane (Right)
- Fields:
- Name (double-click to inline edit)
- Email
- Auth
- Plan
- Last Used
- 5h Remaining
- Weekly Remaining
- Usage Error
- Actions:
- `Switch` (disabled if active or switching blocked)
- `Delete...` (confirmation required)

### Inline Rename Behavior
- Double-click `Name` to edit.
- Submit trims whitespace.
- Empty value rejected.
- Unchanged value treated as no-op.

## Surface 3: Add Account Sheet
### Modes
- `ChatGPT Login`
- `Import auth.json`

### Fields
- Account name (required)
- Path field + file picker for import mode.

### Validation
- Reject empty name.
- Reject empty import path for import mode.
- Show in-sheet validation copy before submission.

## Dialogs
### Close Codex Confirmation
- Warning style `NSAlert`.
- Copy explains process termination impact.

### Delete Account Confirmation
- Warning style `NSAlert` with irreversible action copy.

### Error Alerts
- Critical style `NSAlert` surfaced from runtime errors.

## Interaction Rules
1. Switching blocked when Codex processes are running and target account is not active.
2. Selection reconciliation order in manage window:
- Keep existing selected if still present.
- Else select active account.
- Else select first account.
3. Popover auto-closes on app deactivation.
4. Popover closes for `Switch`, `Manage`, and `Quit` commands.
