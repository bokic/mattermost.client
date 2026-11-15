# TODO — `mattermost.client`

_Reviewed: 2026-11-15 · Revision: `e74d2ee` (tag `0.8.0` + fixes) · Scope: 26 application Swift files (15,617 lines),
8 unit-test files (1,049 lines), `RELEASE.md`, `tools/hud_measure.swift`, Xcode project,
build/release scripts, CI, README/AUDIT._

**Verified baseline at this revision**

| Check | Result |
|---|---|
| `./build.sh` | **Succeeds**, 0 compiler warnings |
| `./test.sh` | **93/93 pass** |
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

- [ ] **No reply count/thread indicator on timeline root posts** — `S`
  - `createPostRow` never shows "N replies" or a participant avatars row, so users cannot
    tell a root has a thread without opening the hover menu. Add the reply footer from the
    web client and refresh it on `thread_updated`/reply.

- [ ] **System messages, presence and bot detection are heuristic** — `S`
  - `MMPost` has no `props`, so system posts with an empty `message` collapse to
    "System update" (`MainWindow+Timeline.swift:1561`) instead of the join/leave/header
    text the web renders.
  - Unknown/not-yet-fetched users default to a green "online" dot
    (`MainWindow+Timeline.swift:1910`); Mattermost treats a missing status as offline.
  - Bot detection is a username substring check (`:1688-1691`), so humans named "abbott" get
    a BOT badge while a bot named `ci` does not.
  - Date separators dedupe by formatted label rather than calendar day (`:2338-2347`), and
    future-dated posts get a weekday because the day difference is negative
    (`TimelineSupport.swift:75-83`).

- [ ] **No link previews** — `M`
  - Mattermost renders Open Graph previews for URLs. The native client leaves bare links.
    Add a metadata fetch (opt-in/privacy aware), card layout, and image proxy/caching.

- [ ] **Reaction UX is limited and partly broken** — `M`
  - The reaction picker is 16 hardcoded emoji (`MainWindow.swift:681-686`,
    `MainWindow+Timeline.swift:1049-1091`): no search, no recent reactions, no custom
    emoji, no "who reacted" tooltip/list.
  - Custom emoji reactions render as literal `:name:` text because `emojiGlyph` only consults
    the bundled catalog and never `customEmojiEntries`/`customEmojiImages`
    (`MainWindow+Timeline.swift:1272-1278`).
  - Chips do not wrap (they run past the row edge and clip), are sorted alphabetically
    instead of by count, and have no reaction-details popover (`:507-567,1280-1288`).
  - Deleted posts still render their reaction chips and allow toggling reactions
    (`:1657,1718-1725,1897-1900`); reaction add/remove is not optimistic and failures only
    log (`:698-721`). The picker also anchors to the last toolbar subview (the ellipsis)
    rather than the emoji button (`:674-679`).
  - Add a searchable picker (reuse the composer picker), custom-emoji glyphs, wrap + detail
    tooltips, optimistic toggles and deleted-post guards.

- [ ] **Attachment and inline-image rendering has several correctness gaps** — `M`
  - Image attachments never set `imageView.animates` and only fetch the static preview, so
    animated GIF attachments appear frozen (`MainWindow+Timeline.swift:1334-1341,1380`).
  - Multiple images stack on separate rows instead of using Mattermost's image grid
    (`:1485-1490`), consuming large vertical space.
  - When `file.width/height` are absent, the preview's downscaled pixel size is cached as the
    natural size (`:1383-1389`), so the image can never render at its true size.
  - Any failed image fetch becomes a hardcoded fake "GIPHY" animation (`:239-273,440,459`),
    including ordinary PNG/JPEG URLs; Giphy page links are treated as images too
    (`:279-286`), so a normal link turns into a fallback GIF instead of a link/preview.
  - Normal Markdown images whose URL has no image extension or query string are dropped by
    `inlineMarkdown` (`:2083-2111`) and not rescued by `parseGiphyInMessage` (`:289-301`).
  - Lightbox zoom has no pan/scroll (`:1004-1023`), so >1× content outside the stage is
    unreachable; the image is also retained after close (`:951-960`).

### Navigation and sidebar

- [ ] **Sidebar category state is not persisted and categories cannot be managed** — `M`
  - Toggling a category only flips the in-memory `isCollapsed`
    (`MainWindow+Sidebar.swift:744-755`); it is lost on relaunch. `isFavoritesCollapsed` is
    also memory-only. There is no create/rename/delete/reorder API use, no channel
    drag-and-drop, and custom categories have no add button (`:492-503`).
  - Done when collapsed state and order persist via the categories API/`UserDefaults`, and
    categories are manageable from the UI.

- [ ] **No channel context menu or unread/mute filtering** — `M`
  - Channel rows only left-click (`MainWindow+Sidebar.swift:702-728`); there is no
    right-click/ellipsis menu, no mute/notification submenu, no mark read/unread, no
    "Unread" filter (only All/Favorites), and no muted-channel styling.
  - `MMSidebarCategory.muted` is decoded (`webservice.swift:211`) but never rendered, and the
    channel menu (`MainWindow+Menus.swift:1029-1056`) has no mute action.
  - Add a context menu sharing the channel-menu actions plus mute, mark read, copy link and
    leave.

- [ ] **Sidebar/team-menu state and styling have several parity bugs** — `M`
  - Native favorites are stored only in the legacy `favorite_channel` preference while the
    server's own `favorites` category is explicitly skipped (`MainWindow+Sidebar.swift:1016`),
    so web-created favorites may be missing and native favorites may not sync back. Favorites
    are a `Set` sorted alphabetically, losing web order (`:143-145,176-180`).
  - The DM hover "×" has no click handler (`:687-697,803`); the Threads row never gets a
    selected state or unread badge (`:702-706,107-134`); unread badges hardcode white text /
    `buttonBg` instead of `sidebarUnreadText`/`mentionBg`/`mentionColor`, and the badge frame
    overlaps the DM close icon (`:114,1047`).
  - The team menu has no scroll view, per-team unread, "Join another team", leave or settings
    entries (`:822-889`); long team names overlap the `+`/chevron, and its light popup colors
    are hardcoded while the background is themed (`:833-871`, `DesignTokens.swift:78-82`),
    making it unreadable on Onyx/Indigo.
  - Favorite toggles are optimistic and never roll back when
    `saveUserPreferences`/`deleteUserPreferences` fails (`MainWindow+Sidebar.swift:51-75`),
    leaving the UI and server inconsistent.
  - Bot rows without a custom avatar lose their tint because the selection renderer clears
    `contentTintColor` for every `isBotBadge` item (`:733,775-798`), so they can render black
    on dark sidebars.
  - Done when these states mirror the web client and custom themes.

- [ ] **Profile is a no-op; there is no user profile view** — `M`
  - The status menu's Profile row (`MainWindow+Menus.swift:487-506`) does nothing. There is
    no profile popover/sheet (avatar, title, timezone, local time, status, DM button), and
    member rows are not clickable (`MainWindow+RightPanel.swift:368-373`).
  - Add a profile view reused by members, mentions, search authors and the current user;
    add "Message" and "Copy username".

### Composer and account

- [ ] **Login window lacks server discovery by email** — `S`
  - The redesigned login window covers password/MFA/SSO, progress, validation,
    show-password and edit-clearing errors, but users still need to know the server URL;
    there is no email-domain based server discovery.

- [ ] **No notification/mute preferences UI** — `M`
  - Settings only exposes zoom, reconnect, account and logout
    (`MainWindow+RightPanel.swift:642-686`). Add desktop notification mode/sound, mention
    keys, channel mute list, theme override (system/light/dark/server) and advanced
    connection details.

- [ ] **System dark mode and native controls do not follow the theme** — `M`
  - `ThemeManager` defaults to Denim (`Theme.swift:361-372`); `builtin(for:)` has no
    `"system"` mapping, and there is no `effectiveAppearance` fallback or user theme
    override. A Mattermost "System" theme therefore falls back to light Denim.
  - Only the emoji and DM pickers force `NSAppearance` (`MainWindow+Composer.swift:25-32`,
    `MainWindow+Menus.swift:815-817`); `NSApp.appearance` is never set, so native search
    fields, alerts, menus and text fields stay light on dark custom themes.
  - Several parsed colors are unused while surfaces hardcode values
    (`sidebarUnreadText`, `sidebarHoverBg`, `sidebarHeaderBg`, `mentionBg`,
    `mentionColor`, `newMessageSeparator`, `errorText` — `Theme.swift:23-41`), so custom
    themes render inconsistently.
  - Done when system appearance is honored, native controls inherit the palette, and all
    parsed theme colors are used or removed.

- [ ] **Custom status is local-only and limited** — `S`
  - It is persisted only in `UserDefaults` (`MainWindow+People.swift:176-181`,
    `MainWindow.swift:208-209`) and never read from server user props, so statuses set on
    the web/another device are invisible here; expired statuses are not cleared.
  - The emoji is a raw text field with no picker/recent statuses, and "custom date and time"
    is not supported (`:127-161`). Clearing ignores server errors and clears local state
    regardless (`:188-199`), allowing local/server divergence.
  - Add a server-backed custom-status read/refresh, an emoji picker, recent statuses and a
    date/time picker.

- [ ] **Direct messages are 1:1 and picker-limited** — `M`
  - `POST /channels/direct` only (`MainWindow+Menus.swift:1003-1023`), picker fetches the
    first 100 team users (`:883-904`) with no pagination, presence, bot/guest distinction, or
    existing-DM state. No group DM creation, and `dmUsers` is not invalidated on team switch
    (`:869-873`), so the previous team's users remain until relaunch.
  - Add search pagination, presence dots, an existing-conversation shortcut, and group DM
    support where permitted.

- [ ] **Browse Channels only lists public channels** — `S`
  - `loadBrowseChannels` filters `type == "O"` (`MainWindow+RightPanel.swift:688-724`), so
    private channels are invisible and join requests are unsupported. Add private-channel
    discovery (where the API allows) and a join-request flow.

- [ ] **No team administration** — `M`
  - Only create/switch team exist (`MainWindow+Menus.swift:1199-1242`). There is no leave
    team, team settings/edit, member management (add/remove/role), or invite-link option.
    Add at least Leave Team and team member management.

### Platform and accessibility

- [ ] **Accessibility is effectively absent** — `M`
  - Custom `RoundedEdgePanel` controls have no accessibility role/label/value, no
    `acceptsFirstResponder`, and no Space/Return activation (`RoundedEdgePanel.swift:10-102`).
    VoiceOver cannot operate the sidebar, menus, timeline toolbar, reaction chips or
    composer buttons. `accessibilityDescription` is only passed to SF Symbol images.
  - Add `setAccessibilityRole/Label/Help`, keyboard focus rings, Space/Return/Arrow
    handling, and an accessibility audit (VoiceOver, Full Keyboard Access, Increase
    Contrast).

- [ ] **No localization; all UI strings are hardcoded English** — `M`
  - Move strings into a String Catalog, use `NSLocalizedString`/`String(localized:)`, and
    add at least one additional locale. Dates already follow `Locale.current`.

- [ ] **No auto-update path** — `M`
  - There is no Sparkle/feed or update check. Add a signed appcast/update mechanism (or
    document that users must download manually) before public distribution.

---

## P4 — Architecture, performance & maintainability

- [ ] **The timeline is fully rebuilt for every post and avatar** — `L`
  - `rebuildTimelineContent` destroys/recreates every row, date separator and attachment
    view (`MainWindow+Timeline.swift:2216-2394`). Every realtime post (`LiveData:384-404`),
    every image load (`Timeline:408-418`), every reaction (`:733`) and every avatar
    completion (`People:308-354`) triggers a full rebuild. There is no cell reuse,
    virtualization or diffing, so a 20-user channel can do ~20 full N-row rebuilds just from
    avatars.
  - Image/attachment rows unconditionally call `fetchFileData(..., preview: true)` and
    `loadGiphyAnimatedImage` each time they are recreated (`:1378-1396,388-403`), so every
    rebuild re-downloads all visible images. There is no in-memory preview image cache.
  - Inline-image render paths perform synchronous disk I/O on the main thread
    (`Data(contentsOf:)` at `:357,433`), and image loads rebuild without preserving the clip
    offset (`:408-419`), so content shifts while reading.
  - Introduce a row diff/update path keyed by post id, cache decoded previews, load disk data
    off-main, and virtualize/lazy-load large channels. This is the main scalability risk.

- [ ] **Caches and fetch tasks are unbounded** — `M`
  - `userAvatarsById` (`MainWindow.swift:430`), `inlineImageSizeCache`,
    `attachmentSizeCache` (`:133-134`), `customEmojiImages` and the GIF disk cache
    (`MainWindow+Timeline.swift:420-463`) have no cap or eviction. Use `NSCache`/LRU caps,
    cancel thumbnail tasks when a panel closes, and prune the GIF cache.

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
2. **Reaction UX gaps** — web-parity reaction controls.
3. **Accessibility/localization pass** — labels, focus traversal and localized strings.
4. **Timeline incremental updates + bounded caches** — scalability for large channels.
5. **Hosted test bundle + coverage/CI/lint migration** — finish the quality tooling work.

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
  attachments/image cards/lightbox, reactions chips with add/remove, hover toolbar,
  block-level Markdown (headings, ordered/nested lists, blockquotes, tables, rules),
  fenced code with language labels, syntax highlighting and copy links, inline
  markdown/mentions/channels/emoji/images, full Mattermost emoji catalog, Giphy rendering.
- **Realtime:** WebSocket posts, presence, typing, reaction refresh, exponential-backoff
  reconnect, wake/network reconnect, connection banner, 15 s status backstop.
- **Sidebar/teams:** scrollable channel sidebar with pinned team/filter header, server
  categories, favorites persisted as user preferences, unread/mention state from paged
  memberships, live Find channel filter, add/browse/join channels, invite email, create
  team + switch, DM creation, channel menu (info/pins/files/favorite/copy/leave).
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
./test.sh       # 93 tests today; keep the count rising
./lint.sh       # swift-format --strict on the migrated allowlist
./run.sh        # manual smoke test
```

Smoke checklist for any change: launch → token restore → switch channels/teams → type a
draft in A, switch to B and confirm it does not follow → scroll history while a message
arrives → send/edit/delete → react/pin/save → open Threads/Members/Files/Mentions/Saved →
upload and download a file → set DND and confirm notifications stop → zoom (⌘0/⌘+/⌘−, pinch,
HUD) → resize/relaunch (frame + RHS width restore) → log out and back in (no state leakage).
