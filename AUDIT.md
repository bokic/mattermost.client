# Project Audit — `mattermost.client`

**Date:** 2026-11-01
**Scope:** All 5,223 lines of Swift, Xcode project settings, build/release scripts, tests, and README.
**Method:** Full source review, clean `xcodebuild`, `./test.sh`, Info.plist/binary inspection, asset inspection.

---

## Verification Results

| Check | Result |
|---|---|
| Clean build (`xcodebuild -scheme mattermost.client`) | **Succeeds** |
| Unit tests (`./test.sh`) | **12/12 pass** |
| Swift compiler warnings | 1: unused `msgHoverBg` at `MainWindow.swift:2324` |
| Asset catalog | All AppIcon PNGs are 512×525 instead of their declared sizes |
| Deployment target | **macOS 27.0** (`LSMinimumSystemVersion`, `minos 27.0`) |
| README compatibility claim | macOS 14.0+ — **contradicted by the binary** |

**Overall assessment:** a polished, well-executed AppKit UI prototype with a working read-only Mattermost sync layer. It is not yet a usable chat client: sending, logout, search, threads, and several menus are cosmetic. Security and reliability gaps would matter for any real deployment.

---

## What Works

- Login with username/password against Mattermost REST API v4, plus token validation on launch.
- Team, channel, sidebar-category, and post fetching; DM title/user resolution.
- Avatar fetching and caching.
- WebSocket receive path for posts, presence, typing, team changes, and sidebar-category events.
- Team switching, collapsible sidebar categories, status-bar item, zoom shortcuts.
- Pure unit tests for URL construction, JSON decoding, and WebSocket event parsing.

---

## Critical / High

### 1. Deployment target contradicts README — High

`README.md:42` states macOS 14.0+, but no `MACOSX_DEPLOYMENT_TARGET` is set in any `XCBuildConfiguration` in `mattermost.client.xcodeproj/project.pbxproj`. Xcode therefore stamps the SDK minimum, which is currently **27.0**. The built app cannot launch on macOS 14–26.

**Fix:** set `MACOSX_DEPLOYMENT_TARGET = 14.0` for the project, app, and test targets, then verify on an older macOS VM.

### 2. Credentials and bearer token stored in plaintext `UserDefaults` — High

`KeychainHelper.swift:13-37` is not a Keychain helper. It stores the account password and bearer token in `UserDefaults`:

- `AppDelegate.swift:33` reads the token.
- `AppDelegate.swift:61` reads the password.
- `AppDelegate.swift:70`, `LoginWindow.swift:166,185` write the token/password.

The README's "secure preference storage" claim (`README.md:36`) is misleading. The sandbox container is still readable by the user and many local processes, and is included in backups.

**Fix:** use `SecItemAdd`/`SecItemCopyMatching` with `kSecClassGenericPassword` and `kSecAttrAccessibleAfterFirstUnlock`, or explicitly document the trade-off.

### 3. Insecure default transport — High

`webservice.swift:216-218` silently prepends `http://` when the user omits a scheme, and `buildURL` always applies the default port (`8065`). Entering `mattermost.example.com` therefore posts login credentials in cleartext.

With no `NSAppTransportSecurity` configuration in the generated Info.plist, arbitrary remote HTTP connections will generally be blocked by ATS anyway — so the default is both insecure and likely non-functional for remote servers.

**Fix:** default to `https` with port 443, validate the scheme, and require an explicit opt-in for cleartext (ideally localhost only).

### 4. "Log out" does not log out — High

The Log out row (`MainWindow.swift:1174-1195`) is created with `createMenuRow`, whose `onClick` only closes menus (`MainWindow.swift:1338-1342`). The token and stored password remain after clicking it, and there is no other way to clear them from the UI.

**Fix:** clear the token/password, disconnect the WebSocket, reset in-memory state, and return to the login window.

### 5. Chat contents written to the system log — High

`NSLog` logs every WebSocket frame verbatim (`webservice.swift:571-575`), including message text, channel names, and user IDs. `checkToken` logs response bodies on failure (`webservice.swift:369`). Unified logging persists these entries.

**Fix:** use `os.Logger`, remove raw-frame logging from production, and mark message/user data as `privacy: .private`.

### 6. The app cannot send messages, despite the README — High (functional)

- `entryView` is created and then permanently hidden and non-editable (`MainWindow.swift:240-243`).
- The composer consists of static labels and decorative buttons; `composerSendButton` has hover styling but **no `onClick`** (`MainWindow.swift:2638-2651`).
- `sendActiveChannelPost` (`MainWindow.swift:3450`) is never called anywhere.

`POST /api/v4/posts` exists in the client but is unreachable from the UI. Other advertised features are similarly cosmetic: Threads (`MainWindow.swift:1496-1505`), Search, Mentions, Saved Posts, Settings, Invite, Help/Product menu rows, and typing-send (`sendUserTyping` is unused).

**Fix:** wire a real `NSTextView`/`NSTextField` editor and the Send action, or correct the README to describe the app as read-only.

### 7. WebSocket never reconnects — High (reliability)

`onWebSocketDisconnected` is declared and invoked (`webservice.swift:490,566`) but **never assigned** in `MainWindow` or `AppDelegate`. There is no retry/backoff and no sleep/wake handling. After a network interruption the UI silently goes stale until relaunch.

**Fix:** add reconnect with exponential backoff, expose connection state in the UI, and reconnect on `NSWorkspace.didWakeNotification`.

---

## Medium

### Functional / correctness

- **Only the latest 60 posts are ever fetched** (`webservice.swift:455-464`). There is no pagination or "load older" path; history beyond page 0 is inaccessible.
- **Channel-switch race:** `fetchAndRenderPosts` applies results without re-checking `activeChannelId` after `await` (`MainWindow.swift:3412-3440`). A slow response can overwrite the currently open channel's timeline.
- **Realtime is inefficient:** every `posted` event triggers a full REST refetch of the channel (`MainWindow.swift:3259-3265`), and `appendRealtimePost` (`MainWindow.swift:3443`) is dead code. Insert the event post directly and debounce.
- **Sidebar avatar/bot updates mutate struct copies:** `for var item in cat.items` (`MainWindow.swift:1669,1747`) discards `isBotBadge` changes. View properties happen to update because they are reference types; model state does not.
- **Zoom is not really zoom:** both windows resize `contentView.bounds` (`MainWindow.swift:3177-3181`, `LoginWindow.swift:114-118`). Text remains the same point size; only layout density changes. The logic is duplicated in two windows.
- **Threads is non-functional:** selecting the Threads row sets `selectedSidebarItemId = "threads"`, but `loadChannelPosts` then fails its channel lookup and renders nothing.
- **Typing is receive-only:** incoming typing events are shown, but `sendUserTyping` is never called.
- **Status and favorites are local only:** selecting Online/Away/DND/Offline does not call the status API, and the star state is not persisted.
- **No logout or credential reset** beyond relaunch/overwrite.

### Architecture / maintainability

- **`MainWindow.swift` is a 3,464-line god class** mixing view construction, manual layout, API orchestration, caching, and WebSocket handling. Split into view components and a view model/controller.
- **Concurrency safety:** `WebService`'s mutable `mToken`, `webSocketTask`, and `wsSequence` are not actor-isolated, while calls originate from multiple `Task`s. Strict concurrency checking is disabled; this will be fragile under Swift 6.
- **Duplicated transport logic:** `login`, `performAuthenticatedRequest`, and `fetchUserImage` each repeat request construction, status handling, and error mapping. Extract one transport function.
- **`NSApp.delegate as? AppDelegate` casts** are used throughout as a service locator (`MainWindow.swift:1620,1645,1705,3257`, etc.). Inject the service instead.

### Privacy / accessibility / appearance

- **No accessibility support:** zero `setAccessibility*`, roles, or labels. Custom `NSView`s used as buttons are invisible to VoiceOver and inaccessible by keyboard.
- **No dark-mode handling:** hardcoded RGB colors and no `NSAppearance`/`effectiveAppearance` usage. Also no contrast or reduce-transparency consideration.
- **No localization:** all strings are hardcoded English; dates are forced to `en_US_POSIX`.
- **No privacy manifest:** `UserDefaults` is a required-reason API for App Store submission (`PrivacyInfo.xcprivacy` missing).

### Performance

- Timeline is fully destroyed and rebuilt on every incoming post and on every avatar load (`MainWindow.swift:2996`, `1697-1700`).
- `DateFormatter` instances are recreated per render (`MainWindow.swift:3018-3024`).
- The team menu is rebuilt on every layout pass (`MainWindow.swift:2144`).
- `preloadDMUsers` runs during layout (`MainWindow.swift:1704`).
- Avatar cache is unbounded (`userAvatarsById`).
- Avatar loading can trigger repeated full timeline rebuilds with many users.

### Reliability / UX

- Most failures only `NSLog`; there is no offline banner, retry UI, or reconnect messaging. Login is the only flow with inline error display.
- `URLSession.shared` uses default timeouts; no explicit timeout, retry, or reachability handling.
- Tasks are not cancelled when switching channels or closing the window.
- Clicking the Dock icon after closing the window does not reopen it (no `applicationShouldHandleReopen`).
- An invalid stored token is not cleared before attempting password login, so stale state is retried on every launch.

### Testing

- The test target compiles a **second copy** of `webservice.swift` directly (`project.pbxproj:179`) instead of using `@testable import`; the `#if canImport(mattermost_client)` guard is effectively dead.
- Only 12 pure unit tests exist. No tests cover login flow, `AppDelegate`, UI layout, navigation, caching, or WebSocket connection lifecycle (only parsing).
- Test naming mismatch: `testBuildURLWithPlainHostAddsHTTPScheme` (`WebServiceTests.swift:15`) actually asserts `http://`.
- No CI workflow, coverage reporting, or lint/format configuration.

### Build / distribution

- `build_release.sh` produces an unsigned, un-notarized DMG with no hardened-runtime signing; Gatekeeper will warn users.
- No privacy manifest, no App Store metadata, and static `MARKETING_VERSION = 1.0`.
- Release build is not explicitly universal; only Debug sets `ONLY_ACTIVE_ARCH = YES`.
- No deployment target, warnings-as-errors, or strict-concurrency settings.
- All AppIcon PNG slots point at 512×525 images, causing asset-catalog warnings and incorrect icon rendering.

---

## Low / Hygiene

- Dead code: hidden `treeView`/`entryView`, `MainWindowDelegate`, `appendRealtimePost`, unused `sysAuthorLabelRef`/`sysTimeLabelRef`/`sysBodyLabelRef`/`usr*` refs, unused sample-post fallback, `mConnected`, `websocketConnected(isConnected:)`.
- `KeychainHelper` is misleadingly named; `webservice` typealias is lowercase; class naming is inconsistent (`LoginWebService` is a user model).
- Magic numbers and hardcoded frames throughout layout code.
- `README.md` overstates capabilities: sending, typing, search, threads, "secure" storage, and macOS 14 support.
- Working tree has an uncommitted comment-only deletion in `RoundedEdgePanel.swift`; harmless.
- `.DS_Store` files exist locally but are correctly untracked/ignored.

---

## Recommended Remediation Order

1. Set the deployment target to macOS 14.0 and verify on an older OS/VM.
2. Move the password and token to the real Keychain; implement logout and credential clearing.
3. Default to HTTPS/443 and require explicit opt-in for cleartext.
4. Remove chat content and identifiers from system logs; adopt `os.Logger` privacy annotations.
5. Wire the composer and Send action (or correct the README to call the app read-only).
6. Add WebSocket reconnect/backoff, post pagination, and stale-response guards.
7. Split `MainWindow`, add accessibility and dark-mode support.
8. Fix test-target architecture, add integration/UI tests, add CI and linting.
9. Sign, harden, and notarize the release DMG; add a privacy manifest.
10. Regenerate the AppIcon set from a correctly sized square source image.

---

## Finding Summary

| # | Severity | Area | Finding |
|---|---|---|---|
| 1 | High | Build | Deployment target is 27.0, not README's 14.0 |
| 2 | High | Security | Password/token stored in plaintext `UserDefaults` |
| 3 | High | Security | Default transport is cleartext HTTP |
| 4 | High | Security/UX | Logout does not clear credentials |
| 5 | High | Privacy | Full chat traffic and response bodies logged |
| 6 | High | Functional | No editable composer or working Send action |
| 7 | High | Reliability | WebSocket disconnects are never recovered |
| 8 | Medium | Functional | Only latest 60 posts; no pagination |
| 9 | Medium | Functional | Channel-switch response race |
| 10 | Medium | Performance | Full REST refetch per realtime post |
| 11 | Medium | Correctness | Sidebar struct-copy updates discarded |
| 12 | Medium | UX | "Zoom" changes layout, not text scale |
| 13 | Medium | Architecture | 3,464-line `MainWindow` god class |
| 14 | Medium | Concurrency | Unsynchronized mutable state in `WebService` |
| 15 | Medium | Accessibility | No VoiceOver/keyboard/dark-mode support |
| 16 | Medium | Testing | Duplicate source in test target; 12 unit tests only |
| 17 | Medium | Distribution | Unsigned/un-notarized DMG; no privacy manifest |
| 18 | Low | Assets | App icons are 512×525 in every slot |
| 19 | Low | Hygiene | Dead code, duplicated transport logic, doc drift |
