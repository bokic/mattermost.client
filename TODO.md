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

- [x] **Threads and the right-hand panel are inert** — `M`
  - Done: a 320 pt right-hand panel with Threads (`GET /users/{id}/teams/{team}/threads`), Members
    (channel members + user hydration) and Pinned Posts (`/channels/{id}/pinned`). The sidebar
    Threads row opens it, the member chip opens Members, the pins icon opens Pinned, and the header
    panel button toggles Threads; rows open the channel and the panel refreshes on channel switch.
  - Remaining: a Files tab in the RHS and true thread-reply rendering (root + replies) inside the
    panel instead of a flat list.

- [x] **Top-right `@`, bookmark and gear do nothing** — `M`
  - Done: all three open the right-hand panel. `@` lists recent mentions (server-side search for
    `@username` because this server version 404s `/users/{id}/teams/{team}/posts/mention`), the
    bookmark lists flagged posts (`/users/{id}/posts/flagged`), and the gear shows an app panel with
    zoom reset, forced reconnect, account/server info and logout.
  - Remaining: a full preferences sheet (notifications, theme, advanced settings).

- [x] **Log out does not log out** — `S`  
  _Done `4ff36b3`: clears token/password, disconnects, shows login._
  - Where: `MainWindow.swift` logout row (≈1327) is built with `createMenuRow`, whose default
    `onClick` only closes menus; token/password remain in `UserDefaults`.
  - Done when: token + stored password are cleared, WebSocket disconnects, in-memory state resets,
    and `LoginWindow` is shown.

- [x] **Sidebar actions are decorative** — `M`
  - Done: `Add Channels` opens a Browse Channels panel with joined/joinable state and join support
    (`POST /channels/{id}/members`); `Invite Members` and the hero invite button open an email
    invite sheet (`POST /teams/{id}/invite/email`); the team `+` opens a create-team sheet
    (`POST /teams`) that refreshes and switches to the new team; the filter button opens an
    All channels / Favorites menu; the Find channel field filters live.
  - Remaining: private-channel join requests, shareable invite links, richer filters
    (unread/mentions), team leaving.

- [x] **Composer action buttons are mock** — `S`
  - Done: the emoji button opens a 40-emoji picker that inserts at the caret; the paperclip opens
    `NSOpenPanel` and uploads through multipart `POST /files`, then posts with `file_ids`, with
    uploading/failure feedback in the composer footer.
  - GIF: the mock local-post button was removed — this server has no Giphy plugin (`/plugins` is
    empty), so the control is hidden instead of faking content. Plugin-backed GIF search remains a
    follow-up.
  - Remaining: render uploaded attachments in the timeline (blocked on the `MMPost` files model).

- [x] **Channel-header controls are partial** — `M`
  - Done: favorites persist via user preferences; the member chip opens the Members panel; the pins
    icon opens Pinned Posts; the title opens a channel menu with View Info, Pinned Posts,
    Add/Remove Favorite, Copy Link (verified in the clipboard) and Leave Channel (DELETE member,
    sidebar refresh and fallback channel).
  - Remaining: mute/notification preferences and channel-settings editing.

---

## P1 — Correctness & reliability

- [x] **Channel-switch race** — `S`  
  _Done: `fetchAndRenderPosts` re-checks `activeChannelId` before applying results._
  - Where: `fetchAndRenderPosts(channelId:)` awaits REST + user + status calls, then
    `applyPostsToTimeline` (≈4362) writes `currentChannelPosts` without re-checking
    `activeChannelId == channelId`. A slow response for a previous channel can overwrite the open one.
  - Done when: results are discarded unless the channel is still active.

- [x] **Every incoming message triggers a full channel refetch** — `S`  
  _Done: WebSocket posts are inserted directly with id-dedupe and lazy author hydration._
  - Where: `ws.onPostReceived` (≈4150) calls `fetchAndRenderPosts`; `appendRealtimePost` (≈4373) is
    dead code.
  - Done when: the `posted` event is inserted directly (with dedupe against REST results) or batched.

- [x] **No pagination / load-older** — `M`
  - Done: `fetchChannelPosts(..., before:)` loads the page preceding the oldest message; scrolling
    near the top (or the "Load older messages" row) prepends it, dedupes by id, hydrates authors and
    re-anchors the viewport by the added height. Exhaustion is detected when a page returns fewer
    than 60 posts, and the state resets per channel.

- [x] **No read state, per-channel unread counts or mentions** — `L`
  - Done: memberships are loaded from `/users/{id}/teams/{team}/channels/members`, giving per-channel
    unread (`total_msg_count − msg_count`) and mention counts rendered as sidebar badges (blue pill
    for mentions, right-aligned white count for unread). Opening a channel marks it read via
    `POST /channels/members/me/view`, zeroes its badges and records `last_viewed_at`; the timeline
    shows a "New Messages" divider above the first post newer than the last view. Incoming WS posts
    increment counts for channels you are not looking at, and the tray/dock/notification path shares
    the same state.
  - Remaining: "mark all as read" (`PUT /users/{id}/teams/{team}/read`), collapsing the divider once
    scrolled past, and mute-based suppression.

- [x] **Post model cannot represent attachments, reactions, pinned posts, edits or deletes** — `M`
  - Done: `MMPost` decodes `metadata.files`/`metadata.reactions` and `file_ids`. The timeline renders
    image previews (`/files/{id}/preview`) and file chips (name + size, click opens the download),
    grouped reaction chips with shortcode→glyph mapping, a gold pin on pinned posts, the ✎ Edited
    indicator, and a "This message was deleted." tombstone for `delete_at > 0`.
  - Also fixed consecutive grouping to break after five minutes, and attachments/reactions on
    grouped (consecutive) rows.
  - Remaining: interactive reactions (add/remove), file thumbnails beyond the preview endpoint, and
    `props`-driven custom attributes.

- [ ] **Custom status is inert; DND expiry is not refreshed** — `S`
  - Where: status menu "Set custom status" row only closes the menu; `dnd_end_time` is sent but not
    re-evaluated after wake.
  - Done when: custom status editor works and expired DND reverts automatically.

- [x] **Sample posts are injected when logged out** — `S`  
  _Done: demo content only renders with an explicit `--demo` flag._
  - Where: `rebuildTimelineContent` (≈3827) fabricates "sarah.connor" posts when not logged in.
  - Done when: demo content is behind an explicit `--demo` flag or removed.

- [ ] **Message rendering gaps** — `M`
  - Where: `formattedMessage` handles bold/italic/strike/link/quote/lists; no code blocks with
    syntax styling, inline images, `@mentions`, `#channel` links, emoji shortcodes, or tables.
  - Done when: these render like the web client and links open in the default browser.

- [ ] **WebSocket reconnect is a fixed 3 s retry** — `S`  
  _Progress: exponential backoff with jitter (1→30 s), reset on connect, and immediate reconnect on `NSWorkspace.didWakeNotification`. Still missing a visible connection state._
  - Where: `webservice.swift` — `scheduleReconnect` uses a constant interval, there is no exponential
    backoff, no jitter, no UI connection state, and no `NSWorkspace.didWakeNotification` handling.
  - Done when: a visible "reconnecting" state exists in the UI.

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
