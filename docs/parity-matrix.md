# Codex Tools Swift Parity Matrix

## Scope
This matrix tracks 1:1 parity between the Rust implementation (`src/`) and the Swift native implementation (`swift-native-port/`).

## Data Contracts
| Contract | Rust Source | Swift Source | Status |
|---|---|---|---|
| `~/.codex-tools/accounts.json` path + env override `CODEX_TOOLS_HOME` | `src/domain/storage.rs` | `CodexToolsCore/Sources/CodexToolsCore/Paths.swift`, `Storage.swift` | Implemented |
| `accounts.json` schema version `2` (strict, no migration) | `src/domain/types.rs`, `src/domain/storage.rs` | `Models.swift` (`AccountsStore`), `Storage.swift` | Cutover Divergence |
| `usage_cache` persistence (`cached_at_unix`) | `src/domain/types.rs`, `src/domain/storage.rs` | `Models.swift` (`CachedUsageEntry`), `Storage.swift` | Implemented |
| `~/.codex-tools/ui.json` + `sidebar_mode` (`compact`/`detailed`) | `src/domain/storage.rs` | `Storage.swift` | Implemented |
| `~/.codex/auth.json` path + env override `CODEX_HOME` | `src/domain/switcher.rs` | `Paths.swift`, `Auth.swift` | Implemented |
| `auth.json` payload (`OPENAI_API_KEY`, `tokens`, `last_refresh`) | `src/domain/types.rs`, `src/domain/switcher.rs` | `Models.swift` (`AuthDotJSON`, `TokenData`), `Auth.swift` | Implemented |
| Secure file permissions `0600` for sensitive files | `src/domain/storage.rs`, `src/domain/switcher.rs` | `Paths.swift`, `Storage.swift`, `Auth.swift` | Implemented |

## Account Lifecycle
| Behavior | Rust Source | Swift Source | Status |
|---|---|---|---|
| Add account via import of `auth.json` | `src/app/actions.rs`, `src/domain/switcher.rs` | `Runtime.swift` (`importFromFile`), `Auth.swift` | Implemented |
| Add account via OAuth | `src/app/actions.rs`, `src/domain/oauth.rs` | `Runtime.swift`, `OAuth.swift` | Implemented |
| Duplicate name rejection | `src/domain/storage.rs` | `Storage.swift` (`StoreDomain.addAccount`) | Implemented |
| Rename (trim, non-empty, duplicate guard, no-op on unchanged) | `src/app/actions.rs`, `src/domain/storage.rs` | `Runtime.swift` (`handleInlineRename`), `Storage.swift` | Implemented |
| Delete account + active reassignment to first remaining | `src/domain/storage.rs` | `Storage.swift` (`removeAccount`) | Implemented |
| Touch `last_used_at` on switch | `src/domain/storage.rs`, `src/domain/mod.rs` | `Storage.swift` (`touchAccount`), `Runtime.swift` | Implemented |

## Switching + Process Gating
| Behavior | Rust Source | Swift Source | Status |
|---|---|---|---|
| Switch writes auth file and updates active account | `src/domain/mod.rs`, `src/domain/switcher.rs` | `Runtime.swift`, `Auth.swift`, `Storage.swift` | Implemented |
| Block switching when Codex processes are running and target is not active | `src/service/runtime.rs` | `Runtime.swift` (`handleSwitchAccount`) | Implemented |
| Process check model (`count`, `can_switch`, `pids`) | `src/domain/process.rs` | `Models.swift` (`CodexProcessInfo`), `ProcessService.swift` | Implemented |
| Process discovery command strategy | `src/domain/process.rs` | `ProcessService.swift` (`ps -eo pid,comm`, strict error propagation) | Cutover Divergence |
| Close Codex process tree termination (TERM -> wait -> KILL) | `src/domain/process.rs` | `ProcessService.swift` | Implemented |

## OAuth
| Behavior | Rust Source | Swift Source | Status |
|---|---|---|---|
| PKCE verifier/challenge generation | `src/domain/oauth.rs` | `OAuth.swift` (`generatePKCECodes`) | Implemented |
| Random state generation | `src/domain/oauth.rs` | `OAuth.swift` (`generateState`) | Implemented |
| Local callback server default `127.0.0.1:1455`, fallback ephemeral | `src/domain/oauth.rs` | `OAuth.swift` (`OAuthCallbackServer.start`) | Implemented |
| Callback path `/auth/callback` | `src/domain/oauth.rs` | `OAuth.swift` | Implemented |
| Strict state validation | `src/domain/oauth.rs` | `OAuth.swift` (`waitForCallback(expectedState:)`) | Implemented |
| Token exchange endpoint `https://auth.openai.com/oauth/token` | `src/domain/oauth.rs` | `OAuth.swift` (`exchangeCodeForTokens`) | Implemented |
| Timeout `300s` and cancellation | `src/domain/oauth.rs` | `OAuth.swift` (`waitForCallback(timeoutSeconds: 300)`, `cancelLogin`) | Implemented |

## Usage
| Behavior | Rust Source | Swift Source | Status |
|---|---|---|---|
| Usage endpoint `https://chatgpt.com/backend-api/wham/usage` | `src/domain/usage.rs` | `Usage.swift` | Implemented |
| Headers: `Authorization`, `User-Agent`, optional `chatgpt-account-id` | `src/domain/usage.rs` | `Usage.swift` | Implemented |
| API-key usage returns structured unavailable error | `src/domain/usage.rs` | `Usage.swift` | Implemented |
| Convert payload windows to minutes with ceil behavior | `src/domain/usage.rs` | `Usage.swift` (`convertPayloadToUsageInfo`) | Implemented |
| Merge stale and cache behavior for usage refreshes | `src/app/actions.rs`, `src/service/runtime.rs` | `Runtime.swift` (`applyUsageUpdates`, `isUsageStale`) | Implemented |

## Polling + Runtime Loop
| Constant/Behavior | Rust Value | Swift Value | Status |
|---|---:|---:|---|
| Service tick interval | `0.05s` | `0.20s` (`AppController` timer) | Cutover Divergence |
| OAuth poll interval | `1s` | `1s` (`oauthPollInterval`) | Implemented |
| Process check interval | `3s` | `3s` (`processCheckInterval`) | Implemented |
| Active account auto refresh | `15m` | `15m` (`activeRefreshInterval`) | Implemented |
| Snapshot publish interval | `30s` | `30s` (`snapshotPublishInterval`) | Implemented |
| Stale threshold | `15m` | `15m` (`SERVICE_STALE_THRESHOLD_SECONDS`) | Implemented |
| Weekly refresh pause threshold | `1.0%` | `1.0%` (`weeklyRefreshPauseThresholdPercent`) | Implemented |

## Ordering + Display
| Behavior | Rust Source | Swift Source | Status |
|---|---|---|---|
| Sort by weekly remaining desc (default path) | `src/service/runtime.rs` | `Runtime.swift` (`orderedAccountsForDisplay`) | Implemented |
| For weekly remaining `<= 3%`, sort by soonest weekly reset (known reset before unknown) | `src/service/runtime.rs` | `Runtime.swift` (`orderedAccountsForDisplay`) | Cutover Divergence |
| Unknown weekly remaining sorted last | `src/service/runtime.rs` | `Runtime.swift` | Implemented |
| Stable tiebreak by original index | `src/service/runtime.rs` | `Runtime.swift` | Implemented |
| Weekly reset countdown `Xd Yh` / `Yh` / `0h` | `src/service/runtime.rs` | `Runtime.swift` (`formatWeeklyResetCountdown`) | Implemented |

## UI Parity
| Surface | Rust Source | Swift Source | Status |
|---|---|---|---|
| Status menu actions: Refresh / Manage / Switch / Close Codex / Quit | `src/status_menu/macos.rs` | `StatusPopoverView.swift`, `AppController.swift` | Implemented |
| Status account line indicators with stale/error fallback | `src/status_menu/macos.rs` | `StatusPopoverView.swift` | Implemented |
| Manage window split layout with compact/detailed sidebar | `src/ui/macos_manage_accounts.rs` | `ManageAccountsView.swift`, `ManageWindowController.swift` | Implemented |
| Inline rename (double click, submit) | `src/ui/macos_manage_accounts.rs` | `ManageAccountsView.swift` | Implemented |
| Add account flow (OAuth / Import auth.json) | `src/ui/macos_add_account.rs` | `AddAccountSheetView.swift` | Implemented |
| Delete + close confirmations | `src/ui/macos_dialogs.rs` | `AppController.swift` (`NSAlert`) | Implemented |

## Test Port Status
| Rust Test Intent | Swift Test File | Status |
|---|---|---|
| Storage behavior + strict schema gate + sidebar mode | `CodexToolsTests/StorageTests.swift` | Implemented |
| Auth switcher file writing + touch account | `CodexToolsTests/SwitcherTests.swift` | Implemented |
| Usage payload mapping + API key unavailable semantics | `CodexToolsTests/UsageTests.swift` | Implemented |
| Percent conversion utility | `CodexToolsTests/UsageTests.swift` | Implemented |

## Known Deviations
1. Swift implementation uses native in-app sheets and `NSAlert` dialogs rather than AppleScript calls.
2. `CodexTools.xcodeproj` is present as a compatibility placeholder; `Package.swift` is the source of truth for build/test.
3. Runtime loop cadence is intentionally coarser in Swift (`0.20s`) to reduce no-op polling overhead.
4. Swift process detection uses a strict single-`ps` source and surfaces command failures instead of silent fallback behavior.
