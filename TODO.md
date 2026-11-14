# TODO — `mattermost.client`

_Reviewed: 2026-11-15 · Scope: all Swift sources (≈7,000 lines), tests, build scripts, README._

Baseline: `./build.sh` succeeds, `./test.sh` passes 14/14. Items below come from a full source
read plus the earlier `AUDIT.md` (some of its findings, e.g. WebSocket reconnect and the status
API, have since been implemented — those are marked accordingly).

Priority legend: **P0** blocking · **P1** correctness/reliability · **P2** security/packaging ·
**P3** web-parity UX · **P4** architecture · **P5** quality/tooling.
Effort: **S** ≤½ day · **M** 1–3 days · **L** >3 days.

---

## P0 — The app is not yet usable as a chat client

- [x] **Composer accepts no input and cannot send** — `L`  
  _Done `4ff36b3`: editable `ComposerTextView` with placeholder, Return/Shift-Return, send state, optimistic insert, typing events._
  - Where: `MainWindow.swift` — `entryView` is created hidden/non-editable (≈263), `composerSendButton`
    has hover styling but no `onClick` (≈2909), and `sendActiveChannelPost(message:)` (≈4380) has no
    callers.
  - Why: the composer is a picture of a composer. Nothing can be typed or posted.
  - Done when: a real editor accepts text, `↩` sends / `⇧↩` newlines, the send button is enabled only
    with content, posts are inserted optimistically, failures surface a retry, and typing events are
    sent (`sendUserTyping`).

- [x] **Search is a static mock** — `M`  
  _Done `50b631a` for messages: real editable field, `/posts/search`, floating results with click-to-open. The Files tab still needs a files search endpoint._
  - Where: `MainWindow.swift` — `searchPopoverInputLabel` is a non-editable label (≈849); Messages/Files
    tabs only swap the placeholder; there is no search API in `webservice.swift`.
  - Done when: `GET /api/v4/teams/{team}/posts/search` is wired, results render, tabs actually filter
    (`from:` / `in:` / `on:` hints work), and `Esc` closes.

- [ ] **Threads and the right-hand panel are inert** — `M`
  - Where: sidebar `Threads` row sets `selectedSidebarItemId = "threads"`, then `loadChannelPosts`
    (≈4314) fails its `channelsById` lookup and returns; `channelSidebarButton` has no action.
  - Done when: Threads opens a real RHS list (`GET /users/me/teams/{team}/threads`), and the header
    icon toggles members/pins/files panels.

- [ ] **Top-right `@`, bookmark and gear do nothing** — `M`
  - Where: `configureIconButton` (≈1548) only wires hover state; no `onClick` is ever assigned to
    `mentionsPanel`, `savedPostsPanel`, `settingsPanel`.
  - Done when: Mentions/Saved open real lists and Settings opens a preferences sheet.

- [x] **Log out does not log out** — `S`  
  _Done `4ff36b3`: clears token/password, disconnects, shows login._
  - Where: `MainWindow.swift` logout row (≈1327) is built with `createMenuRow`, whose default
    `onClick` only closes menus; token/password remain in `UserDefaults`.
  - Done when: token + stored password are cleared, WebSocket disconnects, in-memory state resets,
    and `LoginWindow` is shown.

- [ ] **Sidebar actions are decorative** — `M`
  - Where: `Add Channels` and `Invite Members` rows are `isSelectable: false` (no-op onClick);
    the team `+`, `Find channel` pill and filter button have no `onClick` at all.
  - Done when: channel browser/join, invite dialog, team creation and channel filtering work.

- [ ] **Composer action buttons are mock** — `S`
  - Where: attachment/emoji buttons are visual only; GIF inserts a hard-coded local post
    (`MainWindow.swift` ≈2889) instead of uploading.
  - Done when: emoji picker inserts into the editor, attachment opens `NSOpenPanel` and uploads via
    `POST /files`, GIF posts real content.

- [ ] **Channel-header controls are partial** — `M`
  - Where: favorite star toggles only local `isChannelFavorited` and is not persisted; the pinned
    icon and channel-title dropdown have no behaviour; member chip does not open the members list.
  - Progress: favorites now persist through `/users/{id}/preferences` (add/delete) and refresh per channel.
  - Remaining: pinned posts popover, channel menu, member list.
  - Done when: favorites go through `POST /users/me/preferences`, pinned posts and the channel menu
    open real popovers.

---

## P1 — Correctness & reliability

- [ ] **Channel-switch race** — `S`
  - Where: `fetchAndRenderPosts(channelId:)` awaits REST + user + status calls, then
    `applyPostsToTimeline` (≈4362) writes `currentChannelPosts` without re-checking
    `activeChannelId == channelId`. A slow response for a previous channel can overwrite the open one.
  - Done when: results are discarded unless the channel is still active.

- [ ] **Every incoming message triggers a full channel refetch** — `S`
  - Where: `ws.onPostReceived` (≈4150) calls `fetchAndRenderPosts`; `appendRealtimePost` (≈4373) is
    dead code.
  - Done when: the `posted` event is inserted directly (with dedupe against REST results) or batched.

- [ ] **No pagination / load-older** — `M`
  - Where: `fetchChannelPosts(channelId:page:perPage:)` always runs with page 0 / 60 posts;
    `next_post_id` and `prev_post_id` are decoded but unused.
  - Done when: scrolling to the top loads older pages without jumping, and the timeline keeps scroll
    position.

- [ ] **No read state, unread badges, mentions or notifications** — `L`
  - Where: no `POST /channels/{id}/view`, no unread counters, no dock badge, no notification banners
    or sounds; the web "New Messages" divider is absent.
  - Done when: switching channels marks them read, sidebar rows show unread/mention counts, the dock
    badge reflects mentions, and a local notification fires for mentions/DMs when unfocused.

- [ ] **Post model cannot represent attachments, reactions, pinned posts, edits or deletes** — `M`
  - Where: `MMPost` (`webservice.swift:118`) only decodes `message` + ids; no `metadata.files`,
    `metadata.reactions`, `props`, `is_pinned` handling beyond decoding.
  - Done when: files/reactions/edited/deleted states render and survive decoding tests.

- [ ] **Custom status is inert; DND expiry is not refreshed** — `S`
  - Where: status menu "Set custom status" row only closes the menu; `dnd_end_time` is sent but not
    re-evaluated after wake.
  - Done when: custom status editor works and expired DND reverts automatically.

- [ ] **Sample posts are injected when logged out** — `S`
  - Where: `rebuildTimelineContent` (≈3827) fabricates "sarah.connor" posts when not logged in.
  - Done when: demo content is behind an explicit `--demo` flag or removed.

- [ ] **Message rendering gaps** — `M`
  - Where: `formattedMessage` handles bold/italic/strike/link/quote/lists; no code blocks with
    syntax styling, inline images, `@mentions`, `#channel` links, emoji shortcodes, or tables.
  - Done when: these render like the web client and links open in the default browser.

- [ ] **WebSocket reconnect is a fixed 3 s retry** — `S`
  - Where: `webservice.swift` — `scheduleReconnect` uses a constant interval, there is no exponential
    backoff, no jitter, no UI connection state, and no `NSWorkspace.didWakeNotification` handling.
  - Done when: backoff + jitter, visible "reconnecting" state, and immediate retry after wake.

- [ ] **Typing is receive-only; date/time handling is static** — `S`
  - Where: `sendUserTyping` is never called; dates use `en_US_POSIX` and a fixed `h:mm a` format.
  - Done when: typing is sent while editing, and dates respect the user's locale/time zone.

---

## P2 — Security, privacy & packaging

- [ ] **Credentials are stored in plaintext `UserDefaults`** — `M`
  - Where: `KeychainHelper.swift` is a `UserDefaults` wrapper despite its name; the bearer token and
    account password are written at `LoginWindow.swift:167` and read at `AppDelegate.swift:33,61`.
  - Done when: `SecItemAdd`/`SecItemCopyMatching` (`kSecClassGenericPassword`,
    `kSecAttrAccessibleAfterFirstUnlock`) is used, or the trade-off is documented honestly.

- [ ] **Cleartext HTTP by default and no ATS configuration** — `S`
  - Where: `webservice.buildURL` prepends `http://` when no scheme is given (≈254) and always applies
    port 8065; the built `Info.plist` has no `NSAppTransportSecurity` keys.
  - Done when: `https`/443 is the default, `http` requires explicit opt-in (ideally localhost only),
    and ATS exceptions are scoped.

- [ ] **Deployment target contradicts README** — `S`
  - Where: no `MACOSX_DEPLOYMENT_TARGET` in `project.pbxproj`; the built app advertises
    `LSMinimumSystemVersion = 27.2` while `README.md` claims macOS 14.0+.
  - Done when: the target is set to 14.0 for app + tests and verified on an older OS.

- [ ] **App icons are the wrong size** — `S`
  - Where: every `Assets.xcassets/AppIcon.appiconset/*.png` is 512×525 instead of the declared
    sizes.
  - Done when: each slot has a correctly sized, square PNG.

- [ ] **No privacy manifest** — `S`
  - Where: `UserDefaults` is a required-reason API; there is no `PrivacyInfo.xcprivacy`.
  - Done when: the manifest is added to the app target.

- [ ] **Raw WebSocket payloads are written to the system log** — `S`
  - Where: `webservice.swift:730,735` `NSLog`s entire frames; `checkToken` logs response bodies.
  - Done when: `os.Logger` with `privacy: .private` for message/user data, and raw frames only under
    a debug flag.

---

## P3 — Web-parity backlog

- [ ] **Post hover toolbar** (emoji/reply/more) and reaction chips — `M`
- [ ] **Attachments and inline images** with correct web sizing, thumbnail previews and lightbox — `M`
- [ ] **"New Messages" divider and unread pill** above the first unread post — `S`
- [ ] **Right-hand sidebar** (threads, members, pinned posts, files) with resize/persist — `L`
- [ ] **Saved posts / mentions / settings / invite / channel browser / DM creation** — `M` each
- [ ] **Emoji picker** (server emoji list + recent) — `M`
- [ ] **Server theme support** (read `preferences` theme, custom colors, dark mode) — `M`
- [ ] **Keyboard shortcuts**: ⌘K search, ⌘F in-channel search, `Esc` to close overlays, `↑` to edit
      last message, focus traversal between sidebar/timeline/composer — `M`
- [ ] **Drag & drop files** onto the composer — `M`
- [ ] **Mentions/autocomplete** for `@user`, `#channel`, `:emoji:` while typing — `L`

---

## P4 — Architecture & maintainability

- [ ] **Split `MainWindow.swift` (4,426 lines)** into view components (sidebar, header, timeline,
  composer, menus) plus a view model owning REST/WebSocket state. — `L`
- [ ] **Extract shared window/zoom plumbing** — zoom is duplicated in `MainWindow` and `LoginWindow`
  and implemented by rewriting `contentView.bounds`; factor it into one controller and document the
  scaling model. — `M`
- [ ] **Actor-isolate `WebService`** (`mToken`, `webSocketTask`, reconnect timer) and enable Swift 6
  strict concurrency. — `M`
- [ ] **Inject `WebService`** instead of repeated `NSApp.delegate as? AppDelegate` lookups. — `M`
- [ ] **Remove dead/legacy code**: hidden `treeView` + `sidebarTopBorder`, hidden `entryView`,
  `appendRealtimePost`, `dateSep1/2*` views, `sysAuthorLabelRef`/`usr*Ref` leftovers. — `S`
- [ ] **Centralize design tokens** (theme colors, radii, metrics currently repeated as literals in
  dozens of places). — `M`
- [ ] **Deduplicate HTTP request building** (`login`, `performAuthenticatedRequest`,
  `fetchUserImage` share status/error handling). — `M`

---

## P5 — Quality & tooling

- [ ] **Expand tests**: view-model state, sidebar selection/collapse, date separators, zoom math and
  HUD sizing, error paths and pagination. Currently only URL/JSON/WebSocket decoding. — `M`
- [ ] **Add CI** (GitHub Actions): `./build.sh`, `./test.sh`, plus lint. — `S`
- [ ] **Add SwiftLint/`swift-format` config** and fix the project headermap warning. — `S`
- [ ] **Align README with reality** — it currently advertises working composer, search, threads,
  mentions, saved posts, settings and invite flows. — `S`
- [ ] **Refresh or archive `AUDIT.md`** (dated 2026-11-01, some findings fixed). — `S`
- [ ] **Commit the DOM-inspection tooling** used for parity work (AppleScript/Chrome driver +
  measurement scripts) under `tools/`, so metrics can be re-verified. — `S`
- [ ] **Logging strategy**: keep `DebugLog` for development, add levels and rotation, and stop
  shipping verbose logs. — `S`

---

## How to verify changes

```bash
./build.sh                 # must succeed with no new warnings
./test.sh                  # 14 tests today; grow this number
./run.sh                   # manual smoke test
```

Smoke checklist for any change: launch → token restore → switch channels → scroll timeline →
switch team → change presence → zoom (⌘0/⌘+/⌘−, pinch, HUD) → resize/relaunch (frame restore).
