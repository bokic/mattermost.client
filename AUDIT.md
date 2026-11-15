# Project Audit — `mattermost.client`

**Date:** 2026-11-15
**Scope:** 15,617 lines of Swift across 26 application files and 8 test files (1,049 lines), Xcode project
settings, build/release scripts, tests, and README.
**Method:** Source review, clean `xcodebuild`, `./test.sh`, `./lint.sh`, Info.plist/entitlements
inspection, asset inspection and a live run against Mattermost v12.1.0.

---

## Verification Results

| Check | Result |
|---|---|
| Clean build (`./build.sh`) | **Succeeds** |
| Unit tests (`./test.sh`) | **54/54 pass** |
| Swift mode | **Swift 6** with `SWIFT_STRICT_CONCURRENCY = complete`, zero concurrency warnings |
| Lint (`./lint.sh`) | **Passes** for the migrated allowlist (`swift-format --strict`) |
| Deployment target | **macOS 14.0** (app and tests) |
| App icon set | Correct 16/32/64/128/256/512/1024 px PNGs |
| Privacy manifest | Present (`PrivacyInfo.xcprivacy`, UserDefaults CA92.1 and FileTimestamp C617.1) |
| Transport security | HTTPS/443 default; explicit `http://` limited to local networks by ATS |
| Release distribution | Automated hardened-runtime signing/notarization pipeline; ad-hoc DMG for local CI smoke tests |

**Overall assessment:** the app is a usable Mattermost client. The functional and security
findings from the original audit are resolved. What remains is producing and verifying a real
notarized artifact, accessibility/localization, test-target and coverage work, and timeline
performance.

---

## Open Findings

| # | Severity | Finding | Status |
|---|---|---|---|
| 15 | Medium | Accessibility and system dark-mode support | **Partial** — clickable panels expose button roles/labels, Space/Return activation and a focus ring; a full VoiceOver audit and system-appearance preference are still missing |
| 16 | Medium | Duplicate source in the test target; limited coverage | **Partial** — 54 tests cover URL/JSON/WebSocket, model state, pagination, date separators, zoom, logging and errors; the test target still compiles copies of shared sources and has no coverage gate |

Resolved findings and the previously verified feature list are preserved in git history.

---

## Remaining Work

### Distribution

- `build_release.sh` implements inside-out Developer ID signing, hardened-runtime verification,
  `notarytool` submission/stapling and checksums, and `RELEASE.md` documents the process. A real
  notarized artifact still has to be produced with the Developer ID certificate and notary
  credentials and verified with `spctl` on a clean machine.
- The app has still not been run on an actual macOS 14 host (only the 27.x development host), so
  the documented 14.0 floor is unproven.

### Accessibility & localization

- Custom `NSView` controls have basic button roles/labels and keyboard activation, but there has
  been no VoiceOver, Full Keyboard Access or Increase Contrast audit. Some controls still have no
  explicit label/help text.
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

1. Produce, notarize and verify a Release DMG on a clean macOS 14 machine.
2. Add accessibility labels/help text and run a VoiceOver/keyboard audit.
3. Move the test target to a hosted bundle and add coverage reporting.
4. Profile and diff timeline updates for large channels; cap avatar caches.

---

## How to Re-Verify

```bash
./build.sh     # clean build, zero warnings
./test.sh      # 54 tests
./lint.sh      # swift-format --strict on migrated files
```

Manual smoke: launch → token restore → switch channels/teams → scroll for older pages → send/edit →
react/pin → open Threads/Members/Files/Mentions/Saved → upload/drag a file → zoom (⌘0/⌘+/⌘−, HUD) →
resize/relaunch.
