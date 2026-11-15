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
| Unit tests (`./test.sh`) | **79/79 pass** |
| Coverage | **33.3% line coverage**, enforced by a 30% gate in `test.sh` |
| Swift mode | **Swift 6** with `SWIFT_STRICT_CONCURRENCY = complete`, zero concurrency warnings |
| Lint (`./lint.sh`) | **Passes** for the migrated allowlist (`swift-format --strict`) |
| Deployment target | **macOS 15.0** (app and tests) |
| App icon set | Correct 16/32/64/128/256/512/1024 px PNGs |
| Privacy manifest | Present (`PrivacyInfo.xcprivacy`, UserDefaults CA92.1 and FileTimestamp C617.1) |
| Transport security | HTTPS/443 default; explicit `http://` limited to local networks by ATS |
| Release distribution | Automated hardened-runtime signing/notarization pipeline; ad-hoc DMG for local CI smoke tests |

**Overall assessment:** the app is a usable Mattermost client. All originally reported
functional, security, test-target, performance, accessibility/localization and test-coverage
findings are resolved. What remains is producing and verifying a real notarized artifact.

---

## Open Findings

None. Resolved findings and the previously verified feature list are preserved in git history.

---

## Remaining Work

### Distribution

- `build_release.sh` implements inside-out Developer ID signing, hardened-runtime verification,
  `notarytool` submission/stapling and checksums, and `RELEASE.md` documents the process. A real
  notarized artifact still has to be produced with the Developer ID certificate and notary
  credentials and verified with `spctl` on a clean machine.
- CI builds and tests the app on macOS 15; a notarized Release DMG still needs verification on a
  clean machine.

---

## Recommended Next Steps

1. Produce, notarize and verify a Release DMG on a clean macOS 15 machine.

---

## How to Re-Verify

```bash
./build.sh     # clean build, zero warnings
./test.sh      # 79 tests + coverage gate
./lint.sh      # swift-format --strict on migrated files
```

Manual smoke: launch → token restore → switch channels/teams → scroll for older pages → send/edit →
react/pin → open Threads/Members/Files/Mentions/Saved → upload/drag a file → zoom (⌘0/⌘+/⌘−, HUD) →
resize/relaunch.
