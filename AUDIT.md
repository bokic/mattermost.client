# Project Audit — `mattermost.client`

**Date:** 2026-11-15
**Scope:** 14,892 lines of Swift across 26 application files and 8 test files, Xcode project
settings, build/release scripts, tests, and README.
**Method:** Source review, clean `xcodebuild`, `./test.sh`, `./lint.sh`, Info.plist/entitlements
inspection, asset inspection and a live run against Mattermost v12.1.0.

---

## Verification Results

| Check | Result |
|---|---|
| Clean build (`./build.sh`) | **Succeeds** |
| Unit tests (`./test.sh`) | **48/48 pass** |
| Swift mode | **Swift 6** with `SWIFT_STRICT_CONCURRENCY = complete`, zero concurrency warnings |
| Lint (`./lint.sh`) | **Passes** for the migrated allowlist (`swift-format --strict`) |
| Deployment target | **macOS 14.0** (app and tests) |
| App icon set | Correct 16/32/64/128/256/512/1024 px PNGs |
| Privacy manifest | Present (`PrivacyInfo.xcprivacy`, UserDefaults CA92.1) |
| Transport security | HTTPS/443 default; explicit `http://` limited to local networks by ATS |
| Release distribution | **Unsigned/un-notarized DMG** (see remaining work) |

**Overall assessment:** the prototype has become a usable chat client. The previously reported
blocking functional and security findings are resolved; what remains is distribution hardening,
accessibility/localization, and some test-target and performance cleanup.

---

## Previously Reported Findings

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | High | Deployment target was macOS 27.0 | **Fixed** — 14.0 for project, app and tests |
| 2 | High | Password/token stored in plaintext `UserDefaults` | **Fixed** — Release uses Keychain; Debug uses a documented plaintext store to avoid re-signing prompts |
| 3 | High | Default transport was cleartext HTTP | **Fixed** — HTTPS/443 default, explicit local-network HTTP exception |
| 4 | High | Log out did not clear credentials | **Fixed** — disconnects the socket, clears token/password, returns to login |
| 5 | High | Chat contents written to the system log | **Fixed** — raw payloads gated behind `--debug-ws`/`debugWebSocketLogging`; no secrets logged |
| 6 | High | No editable composer or working Send action | **Fixed** — editable composer, send/edit/delete, typing, uploads, autocomplete, emoji |
| 7 | High | WebSocket disconnects were never recovered | **Fixed** — exponential backoff with jitter, ping timer, wake/network reconnect and a connection banner |
| 8 | Medium | Only the latest 60 posts were fetched | **Fixed** — `before` pagination via `TimelinePager`, load-older on scroll with viewport anchoring |
| 9 | Medium | Channel-switch response race | **Fixed** — results are discarded unless the channel still matches |
| 10 | Medium | Every realtime post triggered a full REST refetch | **Fixed** — posts insert optimistically; reactions fetch only the changed post |
| 11 | Medium | Sidebar struct-copy updates were discarded | **Fixed** — in-place category/item mutation preserves `isBotBadge` and avatar state |
| 12 | Medium | "Zoom" changed layout, not text scale | **Resolved by design** — documented in `WindowZoomController`: bounds scaling makes logical points map to `zoomFactor` screen points, so text scales too |
| 13 | Medium | 3,464-line `MainWindow` god class | **Fixed** — 746-line window shell plus focused extensions and `ChatViewModel` |
| 14 | Medium | Unsynchronized mutable state in `WebService` | **Fixed** — `@MainActor` isolation, explicit callback hops, task-identity stale guards, Swift 6 |
| 15 | Medium | No accessibility/dark-mode support | **Partial** — server themes (including dark palettes) are applied app-wide; VoiceOver labels/roles are still missing |
| 16 | Medium | Duplicate source in the test target; only 12 tests | **Partial** — 51 tests now cover URL/JSON/WebSocket, model state, pagination, date separators, zoom and errors; the test target still compiles a copy of shared sources |

Other fixed items from the original audit: README capability claims, dead prototype views,
unused label references, the headermap build warning, missing CI/lint, magic radii/metrics,
duplicated HTTP request building, and duplicated zoom plumbing.

---

## Verified Working Features

- Login, session/token restore, token-less stored-password login, logout and credential reset.
- Team/channel/category sync, channel switching, favorites, Find channel, unread/mention badges.
- Composer send/edit/delete, typing notifications, file uploads and drag-and-drop, emoji picker,
  `@`/`#`/`:emoji:` autocomplete, keyboard shortcuts.
- Post rendering with attachments, images, reactions, pins, edits, tombstones, lightbox.
- Server-backed search, Threads, Members, Pinned, Files, Mentions, Saved, Settings, Browse Channels,
  invite email and DM creation.
- WebSocket realtime posts, presence, typing, reactions and reconnect banner.
- Server themes, app-level zoom with HUD, window frame restore, status-bar unread badges and
  notifications.
- Debug/release credential stores, scoped ATS, privacy manifest and app icon set.

---

## Remaining Work

### Distribution

- `build_release.sh` still creates an unsigned, un-notarized DMG. Add hardened-runtime signing with
  a Developer ID certificate, `notarytool` submission/stapling and a documented release checklist.

### Accessibility & localization

- Custom `NSView` controls still lack accessibility roles, labels and keyboard activation, so
  VoiceOver cannot operate the sidebar/menus/timeline controls.
- UI strings remain hardcoded English; only dates/number formatting follow the system locale.
- Dark mode follows the server theme rather than the system `effectiveAppearance`. Consider a
  system-appearance preference for servers that have no theme preference.

### Tests

- The test target still compiles copies of `webservice.swift`, `KeychainHelper.swift`, `Theme.swift`,
  `ChatViewModel.swift`, `TimelineSupport.swift` and `ZoomManager.swift` instead of linking the app
  module. Move to a hosted unit-test bundle (`TEST_HOST`/`BUNDLE_LOADER`) and `@testable import`.
- No coverage for window/layout code, authentication flows, reconnect lifecycle or attachment
  upload/send integration beyond the pure transport tests.
- No coverage reporting in CI.

### Performance

- The timeline is still fully rebuilt when a post arrives or an avatar finishes loading. Consider
  diffing rows for large channels.
- Avatar caches are unbounded; consider an LRU cap or `NSCache`.

### Hygiene

- `typealias webservice = WebService` (lowercase) and `LoginWebService` naming remain for
  compatibility; rename when the public surface is stable.
- A few remaining per-view magic numbers are intentional one-offs (avatar sizes, control-specific
  padding) rather than shared tokens.

---

## Recommended Next Steps

1. Harden, sign and notarize the Release DMG; document the release/verification checklist.
2. Add accessibility labels/traits and keyboard activation for custom controls.
3. Move the test target to a hosted bundle and add coverage reporting.
4. Profile and diff timeline updates for large channels; cap avatar caches.

---

## How to Re-Verify

```bash
./build.sh     # clean build, zero warnings
./test.sh      # 51 tests
./lint.sh      # swift-format --strict on migrated files
```

Manual smoke: launch → token restore → switch channels/teams → scroll for older pages → send/edit →
react/pin → open Threads/Members/Files/Mentions/Saved → upload/drag a file → zoom (⌘0/⌘+/⌘−, HUD) →
resize/relaunch.
