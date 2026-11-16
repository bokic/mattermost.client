# TODO — `mattermost.client`

_Reviewed: 2026-11-15 · Revision: `e74d2ee` (tag `0.8.0` + fixes) · Scope: 26 application Swift files (15,617 lines),
8 unit-test files (1,049 lines), `RELEASE.md`, `tools/hud_measure.swift`, Xcode project,
build/release scripts, CI, README/AUDIT._

**Verified baseline at this revision**

| Check | Result |
|---|---|
| `./build.sh` | **Succeeds**, 0 compiler warnings |
| `./test.sh` | **206/206 pass** |
| `./lint.sh` | **Passes** (`swift-format --strict` on the migrated allowlist) |
| Deployment target | macOS 15.0 |
| Release archs | `arm64 x86_64` (universal), `ONLY_ACTIVE_ARCH = NO` |
| Release signing | **Automated Developer ID/hardened-runtime/notarization pipeline**; ad-hoc DMG in CI; a real notarized build still needs the certificate and notary credentials |

Priority legend: **P1** correctness/data loss/reliability ·
**P2** security/privacy · **P3** web parity/UX · **P4** architecture/performance ·
**P5** quality/tooling/docs.
Effort: **S** ≤½ day · **M** 1–3 days · **L** >3 days.

Line references below reflect the original audit revision and may drift as files change.
Finished checklist items are removed from this file and preserved in git history; the broader
completed baseline remains at the end.

---

## P3 — Web-parity backlog

### Message rendering

### Navigation and sidebar

### Composer and account

---

## P4 — Architecture, performance & maintainability

- [ ] **Status polling is expensive and duplicative** — `M`
  - A 15 s timer calls `requestStatuses` plus a REST `POST /users/status/ids` for every known
    user (`MainWindow+People.swift:356-384`), and each result recursively walks the entire
    timeline view hierarchy (`:245-271`). Rely on WebSocket status events, batch REST
    refreshes, and update only visible/known status dots.

- [ ] **Live-data glue is still concentrated in `MainWindow+LiveData`** — `M`
  - `ChatViewModel` is a 44-line state holder; loading, pagination, read state,
    notification routing and reconciliation live in a 541-line window extension. Move
    workspace orchestration into a service/repository layer so it is testable without a
    window and the view components become read-only projections.

- [ ] **`WebService` is a single 1,500-line class** — `M`
  - REST, WebSocket lifecycle, payload parsing, file transfer and debug logging share one
    main-actor type. Split into `APIClient` (typed endpoints), `WebSocketClient` (parsing +
    backoff) and `FileTransfer` with protocol seams; this also makes unit testing auth,
    reconnect and event parsing much easier.

- [ ] **Persistence is ad hoc `UserDefaults`** — `S`
  - Drafts, scroll positions, statuses, emojis and UI state have no unified store or
    migration story. Add a small `SettingsStore`/`DraftStore` abstraction with per-user,
    per-server scoping and schema versioning.

- [ ] **Legacy naming and small dead code** — `S`
  - `typealias webservice = WebService` (`webservice.swift:387`), duplicate
    `import UniformTypeIdentifiers` (`MainWindow.swift:9-12`), unused
    `sendActiveChannelPost` (`MainWindow+Composer.swift:922-938`), `makeMattermostCompassIcon`
    duplication, and test-only launch hooks in production (`MainWindow.swift:519-542`,
    `LiveData:224`, `Sidebar:926`, `--demo`). Remove or gate behind `#if DEBUG`.
  - `channelHeaderBorder` is styled then always hidden (`MainWindow+Layout.swift:28-30,545`).
  - `Dictionary(uniqueKeysWithValues:)` on membership/category arrays traps on duplicate
    server IDs (`MainWindow+Sidebar.swift:86,415`); use a uniquing initializer.
  - Remaining force unwraps: `NSImage(named: "E82F")!` and
    `NSImage(named: "Mattermost Logo")!` at property-init time (`MainWindow.swift:23-24`),
    `contentView!` (`MainWindow+Layout.swift:657`) and `activeTeam!`
    (`MainWindow+Sidebar.swift:826`); `LoginWindow.init(coder:)` (`LoginWindow.swift:18-20`)
    is a `fatalError`.
  - `AppDelegate.websocketConnected(isConnected:)` (`AppDelegate.swift:178-183`) and
    `MainWindow.statusPromptPill` (`MainWindow.swift:350`, shadowed in `createPostRow`) are
    unused dead declarations; `AppDelegate.zoomGestureMonitor` (`AppDelegate.swift:100-141`)
    is never removed and intercepts pinch/scroll zoom gestures on any window (including modal
    sheets and file panels).
  - The theme parser accepts only `#RGB`/`#RRGGBB`/`#RRGGBBAA` (`Theme.swift:322-344`) and
    silently falls back for CSS `rgba()`, named colors and 4-digit hex; document or support
    those formats. The Connect button also lacks a Return key equivalent
    (`LoginWindow.swift:91-95`).
  - `threadItems` is written but never read outside a test (`MainWindow.swift:82-85`,
    `MainWindow+RightPanel.swift:196`); `searchChannelFiles` hardcodes
    `time_zone_offset: 0` (`webservice.swift:1045`); emoji data exists in two sources of
    truth (`MainWindowSupport.swift:159-551` and `MainWindow.swift:667-686`);
    `statusString(for:)`/`indexForStatus` duplicate the same mapping and demo IDs
    `"usr"`/`"sample_usr"` remain in status logic (`MainWindow+People.swift:29-37,65-73,85-86`).
  - `MainWindowViewController` is an empty stub and `ComposerTextView.isFileDropTarget` is
    written but never read (`MainWindowSupport.swift:12-21,597,622-661`).
  - The 60-post page size is duplicated between `MainWindow.swift:304`,
    `TimelineSupport.swift:28` and the `webservice` default (`webservice.swift:984`); use one
    shared constant.

---

## P5 — Quality, tooling & documentation

- [ ] **The test target compiles copies of app sources instead of linking the app** — `M`
  - `project.pbxproj:185-197` lists `webservice.swift`, `KeychainHelper.swift`, `Theme.swift`,
    `ChatViewModel.swift`, `TimelineSupport.swift` and `ZoomManager.swift` as test sources.
    Move to a hosted unit-test bundle (`TEST_HOST`/`BUNDLE_LOADER`) and `@testable import`.
  - Add coverage for authentication/session restore, reconnect/backoff, composer send and
    failure/retry, drafts, WS event parsing (edit/delete/read), search, attachments,
    thread ordering and RHS pagination. Add coverage reporting + a threshold.

- [ ] **CI is Debug-only and does not report coverage** — `M`
  - `.github/workflows/ci.yml` has no caching, no `-resultBundlePath`, no coverage, no
    Release/universal check, no artifact upload and no notarization job. Add a Release job,
    `lipo` verification, coverage, and a signed/notarized release workflow (manual gate).

- [ ] **Lint only covers 15 migrated files** — `S`
  - `lint.sh` explicitly excludes all `MainWindow+*` files, `AppDelegate`, `LoginWindow`,
    `Theme`, `KeychainHelper`, `MMFont` and the project scripts. Reformat the remaining
    files and add them to the allowlist; consider SwiftLint for rules swift-format misses.

---

## Suggested next 10 (highest value first)

1. **Sign, notarize and verify the release artifact** — requires the Developer ID certificate and notary credentials.
2. **Accessibility/localization pass** — labels, focus traversal and localized strings.
3. **Timeline incremental updates + bounded caches** — scalability for large channels.
4. **Hosted test bundle + coverage/CI/lint migration** — finish the quality tooling work.

---

## Completed baseline

The following were verified as implemented at this revision and should not regress. Detailed
history is in git; the original long-form checklist lives in prior commits of this file.

- **Composer:** editable editor, Return/Shift-Return, send/edit via ↑, delete, typing events,
  optimistic send with retry/delete, per-channel drafts, emoji picker with
  categories/search/recents/custom emoji, `@`/`#`/`:emoji:` autocomplete, file attach +
  drag-and-drop, clipboard-image paste, streamed uploads with per-file progress/cancel/retry,
  server-configured size limits, attachment chips, formatting-toolbar chrome, ⌘K/⌘F, Esc
  overlay handling, focus traversal.
- **Search:** real global search field, `POST /teams/{team}/posts/search`, paginated
  Messages/Files results with scroll/load-more, Up/Down/Enter navigation, term highlighting,
  recent searches, working `From:`/`In:`/`On:`/`Before:`/`After:` filter pills, and scoped
  `in:` prefill from ⌘F.
- **Login:** password login with MFA retry, SAML/OAuth provider discovery and in-app SSO
  browser, session-token verification, Keychain persistence, show-password, progress and
  inline validation.
- **RHS:** Threads, Members, Pinned, Files, Mentions, Saved, Settings, Browse Channels;
  paginated thread/member/file/mention/saved/pinned lists with load-more on scroll and
  stale-response guards; member search plus admin/presence grouping and DM click-through;
  thread read state and newest-reply pagination; rich thread reply composer with
  typing/send state; unpin actions and pin-list refresh; file uploader/sort/search/download
  and cached previews; reconnect-aware settings and confirmed logout.
- **Timeline:** 60-post `before` pagination with viewport anchoring, per-channel unread
  badges, mentions, "New Messages" divider + floating jump pill, date separators with
  localized relative labels, 5-minute grouping, edit/delete tombstones, pinned markers,
  clickable reply-count thread footers refreshed from live reply/thread events,
  props-backed system messages, role/is_bot-based bot detection, offline-by-default
  presence and calendar-day date separators including future dates,
  attachments/image cards, animated GIF/WebP attachments, responsive multi-image grids,
  true-size handling when server dimensions are missing, inline Markdown images with or
  without extensions, scrollable zoomable lightbox, opt-in Open Graph link-preview cards
  with cached images, searchable recent/custom-emoji reaction picker, wrapping
  count-sorted reaction chips with participant tooltips and optimistic toggles, hover toolbar,
  block-level Markdown (headings, ordered/nested lists, blockquotes, tables, rules),
  fenced code with language labels, syntax highlighting and copy links, inline
  markdown/mentions/channels/emoji/images, full Mattermost emoji catalog, Giphy rendering.
- **Realtime:** WebSocket posts, presence, typing, reaction refresh, exponential-backoff
  reconnect, wake/network reconnect, connection banner, 15 s status backstop.
- **Sidebar/teams:** scrollable channel sidebar with pinned team/filter header, server
  categories, persisted collapse state and category order, create/rename/delete/move
  category menus, custom-category channel adding, favorites persisted as user preferences,
  unread/mention state from paged memberships, All/Unread/Favorites filters, muted-channel
  styling and badge suppression, channel right-click menus with notifications/mute,
  mark-read/unread, favorites, copy-link and leave, live Find channel filter, add/browse/join
  channels, invite email, create team + switch, DM creation, channel menu
  (info/pins/files/favorite/copy/leave).
- **Status:** custom status with duration, DND expiry normalization, status menu/checkmarks,
  server-backed presence, correct `dnd_end_time` units and custom-status durations.
- **Themes:** Denim/Sapphire/Quartz/Indigo/Onyx + custom palettes, dark detection, app-wide
  application, design tokens for radii/metrics/native accents.
- **Security/packaging:** Keychain in Release (documented debug plaintext store), HTTPS/443
  default with local-network ATS exception, scoped privacy manifest, correct icon set,
  gated payload logging, macOS 15 deployment target, and an automated signing/notarization pipeline.
- **Architecture:** `MainWindow` split into focused extensions, `ChatViewModel`, injected
  `WebService`, `@MainActor` + Swift 6 complete concurrency, deduplicated HTTP request
  building, dead prototype removal, centralized tokens.
- **Tooling/tests:** 54 unit tests across URL/JSON/WS/model/timeline/zoom/errors/logging/
  themes, CI build+test+lint, `swift-format` config, HUD measurement helper under
  `tools/hud_measure.swift`.

---

## How to verify changes

```bash
./build.sh      # must succeed with no new warnings
./test.sh       # 124 tests today; keep the count rising
./lint.sh       # swift-format --strict on the migrated allowlist
./run.sh        # manual smoke test
```

Smoke checklist for any change: launch → token restore → switch channels/teams → type a
draft in A, switch to B and confirm it does not follow → scroll history while a message
arrives → send/edit/delete → react/pin/save → open Threads/Members/Files/Mentions/Saved →
upload and download a file → set DND and confirm notifications stop → zoom (⌘0/⌘+/⌘−, pinch,
HUD) → resize/relaunch (frame + RHS width restore) → log out and back in (no state leakage).
