# TODO — `mattermost.client`

_Reviewed: 2026-11-15 · Revision: `acc4262` (tag `0.8.0` + 1; TODO-only commit after `c0c32c6`) · Scope: 26 application Swift files (14,005 lines),
8 unit-test files (1,048 lines), `tools/hud_measure.swift` (99 lines), Xcode project, build/release scripts, CI, README/AUDIT._

**Verified baseline at this revision**

| Check | Result |
|---|---|
| `./build.sh` | **Succeeds**, 0 compiler warnings |
| `./test.sh` | **51/51 pass** |
| `./lint.sh` | **Passes** (`swift-format --strict` on the 15-file migrated allowlist) |
| Deployment target | macOS 14.0 |
| Release archs | `arm64 x86_64` (universal), `ONLY_ACTIVE_ARCH = NO` |
| Release signing | **Ad-hoc** (`CODE_SIGN_IDENTITY = -`), `ENABLE_HARDENED_RUNTIME = NO`, not notarized |

Priority legend: **P0** release blocker · **P1** correctness/data loss/reliability ·
**P2** security/privacy · **P3** web parity/UX · **P4** architecture/performance ·
**P5** quality/tooling/docs.
Effort: **S** ≤½ day · **M** 1–3 days · **L** >3 days.

Application source is unchanged from `c0c32c6`; line references therefore refer to that
source revision. The long list of previously completed work is preserved in
[Completed baseline](#completed-baseline) at the end.

---

## P0 — Release blockers

- [x] **The release DMG is not signed, hardened, or notarized** — `M`
  - `build_release.sh` only runs `xcodebuild -configuration Release` and `hdiutil create`.
    `xcodebuild -showBuildSettings -configuration Release` reports
    `CODE_SIGN_IDENTITY = -`, `ENABLE_HARDENED_RUNTIME = NO`, and no `DEVELOPMENT_TEAM`.
  - Gatekeeper will reject the app on other Macs. Done when the `.app` is Developer ID
    signed with the hardened runtime, submitted with `notarytool`, the ticket is stapled,
    and `spctl --assess` passes on a clean machine.
  - Add the signing identity/team to the Release configuration or pass it from CI; keep
    `--deep`-free, inside-out signing for nested code.

- [x] **No Release/notarization CI job, and no clean-machine smoke test** — `M`
  - `.github/workflows/ci.yml` only builds/tests/lints Debug on `macos-15`. Nothing builds
    Release, verifies `lipo -archs` is `x86_64 arm64`, signs, notarizes, or uploads an
    artifact + checksum.
  - Done when CI produces a verifiable Release artifact (even if signing is a protected
    manual job) and a smoke launch succeeds on a clean runner.
  - Also outstanding: the app has still not been run on an actual macOS 14 host (only the
    27.x development host), so the documented 14.0 floor is unproven.

---

## P1 — Correctness, data loss & reliability

### Interaction and input

- [x] **Clicks on icon-only buttons and image thumbnails are dead zones** — `M`
  - Every clickable surface is a `RoundedEdgePanel` with child `NSImageView`/`NSTextField`
    views. `hitTest` returns the child (`RoundedEdgePanel.swift:96-102` does not override
    `hitTest`). I verified with AppKit that `NSImageView`'s `mouseDown` does **not** forward
    to the parent, while `NSTextField` labels do.
  - Result: icon-only controls (top-right `@`/bookmark/gear, Help, search, channel star/
    members/pins/files/sidebar/info, composer emoji/attach/send, download/lightbox buttons)
    only work in the few pixels of padding around the icon; clicking the icon itself does
    nothing. Attachment thumbnails and image previews have the same dead center. Menu rows
    work on their text but not their icons.
  - Fix by overriding `hitTest` on clickable panels to return `self` (or making children
    non-hit-testable) and add a synthetic click test for icon-only buttons.

- [x] **The "N new messages" jump pill is a full-width clickable bar** — `S`
  - `newMessagesPill.frame` is `listRight - 30` wide (`MainWindow+Layout.swift:642-647`);
    `layoutNewMessagesPill` only centers the icon/text inside it
    (`MainWindow+Timeline.swift:83-92`). It renders as a blue strip across the timeline and
    swallows clicks in that strip. Size the panel to the text group plus padding.

- [x] **Tab / Shift+Tab inside the message composer jumps focus out instead of editing** — `S`
  - `MainWindow.sendEvent` (`MainWindow.swift:554-628`) intercepts `keyCode == 48` (Tab)
    whenever `currentFocusRegion()` is `.composer`, `.sidebar`, or `.timeline` and cycles
    focus to the next region. Pressing Tab inside `entryView` (e.g., to indent a list item or
    code block) immediately moves focus out of the composer.

### Composer and drafts

- [x] **Drafts are not per-channel and can be sent to the wrong channel** — `M`
  - Nothing stores or clears composer text on channel switch. The sidebar row click
    (`MainWindow+Sidebar.swift:716-727`) calls `loadChannelPosts`, which only calls
    `cancelEditing()`/`clearPendingAttachments()` (`MainWindow+LiveData.swift:242-281`);
    `entryView.string` is never cleared outside send/edit (`MainWindow+Composer.swift:857,877`).
  - Typing in #a then opening #b leaves #a's text in the composer, where Return sends it to
    #b. Done when each channel/thread has an independent draft (in memory at minimum,
    preferably Mattermost `drafts` API), switching restores it, and pending attachments are
    scoped to the channel that uploaded them.

- [x] **Sending is not optimistic and has no retry or failure recovery** — `M`
  - `sendComposerMessage` (`MainWindow+Composer.swift:864-920`) clears the editor *before*
    awaiting `POST /posts`, shows "Sending…" in the Help label, and only appends the post
    after the server responds. On failure it restores the text only if the composer is
    still empty, then hides the error after 4 s.
  - There is no pending/sending timeline row, no Retry/Delete action, and no offline queue.
    Done when a post appears immediately with a sending state, failure leaves a retryable
    row, and the draft survives channel switches/relaunch (see drafts above).
  - `sendActiveChannelPost` (`:922-938`) is an unused older send path; remove it.

- [ ] **Attachment uploads are all-or-nothing, sequential, and unbounded** — `M`
  - `uploadFiles` (`MainWindow+Composer.swift:652-692`) reads each file fully into memory
    (`Data(contentsOf:)`) and uploads sequentially with no size check, progress, cancel, or
    per-file error. Partial successes are silently kept, failures are ignored.
  - No clipboard-image paste, no attachment preview before send, and no upload retry.
  - Done when uploads stream/chunk (or at least cap size), show per-file progress/errors,
    can be cancelled, and server file-size limits are surfaced before uploading.

- [x] **Attachment downloads can fail silently and write untrusted filenames** — `S`
  - `saveFileData` (`MainWindow+Timeline.swift:1535-1543`) uses `try? data.write(to:)`, so a
    sandbox denial or disk error is invisible. The app is sandboxed with
    `com.apple.security.files.user-selected.read-only`
    (`mattermost.client/mattermost_client.entitlements`); confirm a `NSSavePanel` grant can
    actually be written, or add the read-write user-selected entitlement.
  - `openAttachment` (`:1516-1525`) writes to `temporaryDirectory` using the server-supplied
    `file.name` without sanitizing `/`, `..`, or collisions; it also never cleans up.
  - Done when saves report success/failure, filenames are sanitized, temp files are cleaned,
    and the entitlement matches the write path.

- [x] **Typing indicator has a 3-second timer race and clobbers composer status** — `S`
  - `ws.onUserTyping` (`MainWindow+LiveData.swift:115-123`) sets
    `composerHelpLabel.stringValue = "\(typer) is typing..."` and schedules an uncancelled
    `DispatchQueue.main.asyncAfter(deadline: .now() + 3.0)` to reset it to `"Help"`.
  - Overlapping typing events clear early when the first timer fires, and the timer
    unconditionally overwrites `"Editing • Esc to cancel"`, `"Uploading…"`, `"Sending…"`, and
    `"Attached N files"` states in `composerHelpLabel`.
  - It also ignores `parentId`: thread typing events appear in the main channel composer, and
    the thread RHS composer has no typing indicator.

### Realtime and read state

- [ ] **Realtime edit/delete/channel/read events are not handled** — `L`
  - The WebSocket parser only understands `hello`, `posted`, `status_change`, `typing`,
    `update_team`, `added_to_team`, `leave_team`, sidebar category updates and reactions
    (`webservice.swift:327-339,1376-1450`; dispatch `:1470-1497`).
  - Missing events include at least `post_edited`, `post_deleted`, `channel_updated`,
    `channel_viewed` / `multiple_channels_viewed`, `preferences_changed`, `thread_updated`,
    `post_unread`, channel `user_added`/`user_removed`, and `emoji_added`.
  - Consequence: edits/deletes/pins/theme changes/read-state changes made by other clients
    are invisible until a manual channel reload. Done when they update the model, timeline,
    RHS and badges in place.
  - Even for handled events, neither `onPostReceived` nor `handleIncomingPost` refreshes the
    open right panel, and `applyUpdatedPost` updates either the timeline or the thread panel
    but not both (`MainWindow+Timeline.swift:723-735`). Threads/Pinned/Mentions/Saved lists
    stay stale until reopened. After reconnect, only statuses are refreshed
    (`MainWindow+LiveData.swift:86-89`); messages missed while disconnected are never fetched.

- [x] **Read state is local-only; there is no "mark all as read"** — `M`
  - `markActiveChannelViewed` (`MainWindow+LiveData.swift:25-39`) only sends
    `POST /channels/members/me/view` for the open channel. Incoming `channel_viewed` events
    from another device are ignored, and there is no
    `PUT /api/v4/users/{id}/teams/{team}/read` action.
  - Done when other clients' reads clear badges here, a "Mark all as read" action exists
    (sidebar/channel menu), and per-channel "Mark read/unread" is available.
  - `markActiveChannelViewed` also clears local unread/mentions even when the view API call
    fails (`MainWindow+LiveData.swift:30-38`), so a transient failure silently hides real
    unread state.
  - The Dock/menu-bar unread count is a separate in-memory `AppDelegate.unreadCounts` map
    (`AppDelegate.swift:24,201-257`). It resets on relaunch and is not initialized or
    reconciled from server membership unread totals, so it can disagree with the sidebar.
    Derive these indicators from shared server-backed unread state and refresh them at
    launch/reconnect.

- [x] **DND and per-channel notification preferences do not suppress notifications** — `M`
  - The status menu says DND "Disables all notifications"
    (`MainWindow+Menus.swift:396`), but `handleIncomingPost`
    (`MainWindow+LiveData.swift:415-445`) calls `noteIncomingMessage` unconditionally;
    `AppDelegate.noteIncomingMessage` (`AppDelegate.swift:201-257`) always posts a banner +
    sound.
  - `notify_props` (`desktop`, `desktop_sound`, `mention_keys`, `desktop_threads`) and
    channel mute are decoded/available but never applied. Muted channels still increment
    badges and notify.
  - Done when DND, offline, `desktop: none`, `desktop: mention`, sound off, mention-key
    overrides and channel mute are honored, including thread replies.

- [x] **DND expiry and "Don't clear" custom status are broken** — `S`
  - Mattermost returns `dnd_end_time` in **seconds** (confirmed in
    `server/public/model/status.go`), but `normalizedStatus` compares it to `nowMs`
    (milliseconds) (`MainWindow+People.swift:220-224`). Every future DND expiry is therefore
    treated as expired and the next 15 s poll flips the user to online.
  - The custom-status duration list sends `"dont_clear"` for index 0
    (`MainWindow+People.swift:168-170`), but the server's valid set is `""`,
    `thirty_minutes`, `one_hour`, `four_hours`, `today`, `this_week`, `date_and_time`
    (`server/public/model/custom_status.go`). "Don't clear" is rejected, so most custom
    statuses fail with an alert; send an empty duration and no `expires_at`.
  - "This week" is implemented as now + 7 days rather than the end of the week
    (`:201-218`), and expired custom statuses are never auto-cleared.

- [x] **Incoming realtime posts steal the scroll position** — `S`
  - `appendRealtimePost` (`MainWindow+LiveData.swift:384-404`) always calls
    `rebuildTimelineContent(scrollToBottom: true)`. If the user is reading history, a new
    message jumps them to the bottom.
  - Done when new posts only auto-scroll if the view was already at/near the bottom; expose
    the floating "N new messages" jump pill otherwise.
  - Note: `appendRealtimePost` does not update `newMessagesCount`/`newMessagesDividerPostId`
    (`MainWindow+LiveData.swift:384-391`), so even the current pill never appears for live
    traffic.

- [x] **Scroll position is not remembered per channel** — `M`
  - `loadChannelPosts` clears posts and `applyPostsToTimeline`
    (`MainWindow+LiveData.swift:332-351`) always scrolls to bottom or the unread divider.
    Returning to a channel loses where you were.
  - Done when each channel restores its last visible post/offset (Mattermost does this).

- [x] **Notification click opens the channel, not the message** — `S`
  - `postNotification` stores only `channelId` (`AppDelegate.swift:240-257`) and
    `didReceive` calls `openChannel(withId:)` (`:267-279`). Done when the notification
    carries the post/thread id and opens/highlights the exact message.

### Search

- [x] **The Files tab in global search is a dead control** — `M`
  - Selecting Files only changes the placeholder (`MainWindow+Header.swift:446-458`);
    `performSearchFromPopover` (`:258-283`) always calls `POST /teams/{team}/posts/search`.
  - The service already has `searchChannelFiles` (`webservice.swift:1036-1049`), so a
    team-wide files query can reuse `POST /teams/{team}/files/search` and render the RHS
    file-card style. Done when the tab actually searches files and opens images/files.

- [x] **Search results do not jump to the selected post** — `S`
  - `openSearchResult` (`MainWindow+Header.swift:348-354`) only opens the channel; unlike
    Mentions/Saved (`MainWindow+RightPanel.swift:587-592`), it never sets
    `pendingJumpPostId`, so users land at the bottom of the channel.
  - Done when clicking a result fetches the post if needed, scrolls to it, and highlights it.

- [ ] **Search is first-page-only and mouse-only** — `M`
  - `presentSearchResults` hard-caps at `posts.prefix(50)` (`MainWindow+Header.swift:295`)
    with no "load more", no result highlight, no keyboard navigation, and no recent
    searches. Filter pills (`From:`, `In:`, `On:`…) are decorative.
  - Done when search paginates, supports Up/Down/Enter, highlights terms, and the filter
    pills insert valid scopes.

### Threads and the right-hand panel

- [ ] **Threads lack read state, a rich composer, and pagination** — `L`
  - Opening a thread (`loadThread`, `MainWindow+RightPanel.swift:236-260`) never calls
    `PUT /users/me/teams/{team}/threads/{id}/read`, so unread thread replies never clear.
    The `ThreadsResponse` totals (`total_unread_threads`, etc.) are discarded
    (`webservice.swift:975-981`), and the Threads sidebar row never shows unread.
  - The reply field is a single-line `NSTextField` (`:60-90`): no multiline, emoji,
    `@`/`#`/`:emoji:` autocomplete, attachments, typing events, or send state.
  - The thread list fetches 60 threads (`webservice.swift:975-982`) with no load-more and
    no unread indicator; thread replies are not paginated.
  - `loadThread` has no root/request token (`:243-259`): a late response for thread A can
    overwrite thread B, and replies can be posted to the wrong root. On fetch failure,
    `showThread` leaves the preloaded `[post]` in place so no error is shown (`:223-233`).
  - `renderThreadPanel` scrolls to zero after every load/reply (`:323`), so long threads open
    at the oldest post and the new reply is off-screen.
  - Clicking a row in the Threads list jumps to the root in the channel and closes the panel
    instead of opening the thread (`:210-215`).
  - Verify reply ordering: `renderThreadPanel` uses `list.order` as-is
    (`MainWindow+RightPanel.swift:249`), while channel posts reverse it via
    `MMPostList.chronologicalPosts` (`webservice.swift:313`). If the API returns newest
    first, the root/replies render backwards.

- [x] **Thread replies are rendered inline in the channel timeline** — `M`
  - `rebuildTimelineContent` renders every `currentChannelPosts` entry with no `root_id`
    filter (`MainWindow+Timeline.swift:2336-2371`), and `appendRealtimePost`
    (`MainWindow+LiveData.swift:384-391`) appends any `posted` event for the active channel.
    A reply sent from the RHS thread therefore also appears as a full message in the center
    feed and counts toward history/pagination. Confirm whether `/channels/{id}/posts` already
    excludes replies; filter `root_id` on both paths regardless, and refresh the root's reply
    count instead.

- [ ] **Every RHS list is first-page-only** — `M`
  - Members: 60 (`webservice.swift:822-832`), Threads: 60 (`:975`), Files: 60 (`:1036`),
    Saved: 60 (`:846`), Mentions: 30 (`MainWindow+RightPanel.swift:571`), Pinned: no
    pagination. None load more on scroll.
  - Members also have no search, role/presence grouping, pagination, or click-through to a
    profile/DM (`loadChannelMembers`, `MainWindow+RightPanel.swift:349-378`).
  - `loadUnreadState` fetches one page of 200 memberships (`MainWindow+Sidebar.swift:85`,
    `webservice.swift:882-890`), so users in more than 200 channels lose badges for the rest.

- [ ] **RHS panels have stale/list-detail bugs** — `M`
  - Loaders do not cancel or check the current mode/channel: closing or switching panels
    leaves old rows visible, and a late response can overwrite the new panel
    (`MainWindow+RightPanel.swift:159-162,764-788`).
  - Threads/Mentions/Saved set the channel-name subtitle even though they are not
    channel-scoped (`:108-116`), which is misleading.
  - Pinned rows use the raw message as title (attachment-only pins render blank), have no
    unpin action, and do not refresh after `togglePin` (`:380-415`,
    `MainWindow+Timeline.swift:1225-1242`).
  - Files do not show the uploader despite hydrating users, are not date-sorted, re-fetch
    every preview with no cache, and have no download/search/filter controls
    (`:417-434,450-556`).
  - `hydrateUsers` silently swallows failures (`:748-762`), so rows show raw 26-character
    user IDs or "Unknown"; member role logic only distinguishes `channel_admin` from
    `channel_user` and ignores team/system admin, guest and bot roles (`:363-373`).
  - Reconnect reloads the panel immediately after `reconnectIfNeeded`, so it often still says
    "Reconnecting…" (`:659-669`); Logout has no confirmation (`:676-683`).

### Sidebar, navigation and layout

- [ ] **The channel sidebar is not scrollable** — `M`
  - The sidebar is laid out entirely with fixed frames and has no `NSScrollView`
    (`MainWindow+Sidebar.swift:941-1053`). Once categories/channels exceed the panel height,
    rows get negative Y positions and become clipped/unreachable.
  - Done when the sidebar has a scroll view (with stable hit-testing and hover state) and the
    team/filter/threads header stays pinned.

- [x] **The Favorites filter always shows zero channels** — `S`
  - `visibleItems` requires both `!favoriteChannelIds.contains($0.id)` *and*, when
    `sidebarFavoritesOnly` is true, `favoriteChannelIds.contains($0.id)`
    (`MainWindow+Sidebar.swift:1017-1021`). The conjunction is impossible.
  - Category headers are only hidden when a text query exists (`:1022-1025`), so selecting
    Favorites leaves every header visible with no rows. Done when the filter shows exactly
    the favorite channels (and an empty state).

- [x] **Channels from other teams leak into the active sidebar** — `M`
  - `switchActiveTeam` merges `GET /users/me/channels` (all teams) into `channelsById`
    (`MainWindow+Sidebar.swift:906-921`). `populateSidebarCategories` then appends every
    "unplaced" channel to the current team's CHANNELS section (`:519-543`), so other teams'
    channels and favorites appear here; `channelsByName` is polluted too (`:143-145`), so
    name lookups can resolve another team's channel.
  - Done when the directory is scoped per team (or lookups always check `team_id`) and
    switching teams fully replaces the channel/category state.

- [x] **Team switching is racy, unpersisted, and can show stale data** — `M`
  - A switch updates the header before fetching (`MainWindow+Sidebar.swift:897-900`), has no
    rollback/error UI, and no request token: an older team's slower response can overwrite a
    newer switch (`:901-938`). `loadUnreadState` (`:78-105`) has the same race, and
    `loadChannelPosts` (`MainWindow+LiveData.swift:278-280`) spawns unstructured `Task`s for
    `fetchAndRenderPosts(channelId:)` without cancelling in-flight tasks on rapid channel
    switches.
  - Clicking the already-active team reloads everything and resets selection to Town Square.
    Neither the last active team nor the last channel is persisted
    (`MainWindow+LiveData.swift:196-231`); startup always picks `teams.first`.
  - Done when switches are token-guarded/cancelled, failures revert, clicking the active team
    is a no-op, and the last team/channel is restored.

- [x] **Group Direct Messages (`type == "G"`) are unhandled across the app** — `M`
  - Mattermost has four channel types: `"O"` (open), `"P"` (private), `"D"` (1:1 DM), and
    `"G"` (group DM, up to 7 participants).
  - In `MainWindow+Sidebar.swift:153-158,441-448,519,528`, `"G"` channels fall into the
    `default` branch, receive a public `"globe"` icon, and get placed into `CHANNELS` instead
    of `DIRECT MESSAGES` when uncategorized.
  - In `MainWindow+LiveData.swift:267-271`, `"G"` channels display the public-channel hero
    copy (*"Everyone automatically becomes a member of this channel when they join the team"*).
  - In `MainWindow+Composer.swift:361`, `#`/`~` channel autocomplete excludes `"G"` channels.
  - Done when `"G"` channels render in Direct Messages with group icons/member counts, proper
    hero copy, and autocomplete support.

- [ ] **The RHS overlays the timeline instead of reflowing it** — `M`
  - The timeline is always sized to the full `chatW` (`MainWindow+Layout.swift:640-653`)
    while the panel is a sibling overlay, so opening Threads/Members/etc. covers the right
    side of messages (the web client shrinks the center column).
  - `closeRightPanel` only hides the panel and never calls `layoutRightChatPanel`
    (`MainWindow+RightPanel.swift:159-162`), leaving the new-messages pill/frames stale.
    Panel documents are rendered once at their old width and are not reflowed on
    open/resize/zoom (`Layout:493-540`, `RightPanel:764-788`).
  - Done when the timeline/column resizes around the panel, and closing it or resizing the
    window re-lays out both the frame and the panel content.

- [x] **Header member count is fake and the info button is dead** — `S`
  - `channelMembersCountLabel` starts at `"1"` (`MainWindow.swift:312`) and is never updated
    from `fetchChannelMembers` (`MainWindow+Layout.swift:94-99,570-580`).
  - `channelInfoButton` has no `onClick` (`Layout:166-179`), even though the channel menu’s
    View Info exists. Wire both to real channel info/member data.

- [x] **Login cannot handle subpath deployments or a missing token** — `M`
  - A server URL with a path (`https://host/mattermost`) is accepted, but `buildURL`
    overwrites `components.path` with `/api/v4/...` (`webservice.swift:453`), silently
    dropping the subpath. Mattermost behind a reverse proxy/subpath cannot log in.
  - A successful login response without a `Token` header still calls `showMainWindow()`
    (`LoginWindow.swift:164-167`), opening an unauthenticated window with no data.
  - Also: host/port/username/password are saved before validation (`:142-152`), so a typo
    overwrites previously working saved credentials; clearing the port leaves the old value
    stored (`:45-47`).
  - Done when base paths are preserved in every REST/WS URL, a missing token is a visible
    error, and credentials are stored only after a successful validation.

- [x] **Mention detection misses `@here`/`@channel` and false-positives** — `S`
  - `handleIncomingPost` uses a raw lowercase substring check for `"@" + username`
    (`MainWindow+LiveData.swift:429-433`). It misses `@here`/`@channel`/`@all`, matches
    emails/code/quotes, and counts mentions in muted channels.
  - Done when mention counting uses Mattermost’s mention rules (including special mentions
    and `mention_keys`) and survives edits/deletes.

### Lifecycle, layout and rendering correctness

- [x] **Font fallback in `MMFont.font(ofSize:weight:)` has infinite recursion** — `S`
  - Despite the header comment claiming graceful degradation to the system font
    (`MMFont.swift:7`), the `else` branch when `NSFont(name: postScriptName(for: weight), size: size)`
    returns `nil` calls `return MMFont.font(ofSize: size, weight: weight)` (`MMFont.swift:57`)
    instead of `NSFont.systemFont(ofSize: size, weight: weight)`, causing an immediate stack
    overflow crash if `OpenSans.ttf` is missing or fails to register.

- [x] **Offline or transient 5xx at launch invalidates the session and drops to Login** — `S`
  - `WebService.checkToken` (`webservice.swift:629-649`) catches *all* errors (including DNS,
    offline, timeout, and 5xx) and returns `false`. `AppDelegate.startAuthentication`
    (`AppDelegate.swift:70-82`) then assumes the stored token is invalid and falls back to
    `loginWithStoredPassword`, which also fails offline and forces the user back to
    `LoginWindow`. Distinguish `HTTP 401` from transient network/server errors and open the
    workspace in a reconnecting state when a token exists.

- [x] **Logout leaves user-scoped state behind** — `M`
  - `AppDelegate.logout` (`AppDelegate.swift:320-329`) disconnects and deletes credentials,
    but does not clear `unreadCounts`, the dock badge, delivered notifications, custom
    status, recent emojis, favorites, or the status polling timer.
  - `MainWindow.deinit` (`MainWindow.swift:697-699`) removes NotificationCenter observers
    but never invalidates `statusPollingTimer` (created at `MainWindow+LiveData.swift:167-172`),
    so the timer keeps firing for the app lifetime.
  - Done when logout resets all per-user state and timers, and the next login cannot inherit
    the previous account's status/emoji/unread data.

- [x] **`showMainWindow()` does nothing when a window already exists** — `S`
  - `AppDelegate.swift:281-285` does `guard mainWindow == nil else { createMainWindow(); return }`;
    `createMainWindow()` immediately returns because `mainWindow != nil`. It should bring the
    existing window forward. Add `applicationShouldHandleReopen` too, so Dock activation
    reopens a hidden/closed window.

- [x] **No minimum window size; layout can produce negative widths** — `S`
  - No `minSize`/`contentMinSize` is set anywhere (`MainWindow.swift:438-546`). At narrow
    widths `composerW - 234` (`MainWindow+Layout.swift:596-607`) becomes negative, the
    search field/Help button can overlap the right cluster (`:698-703`), and the right panel
    can be wider than the chat panel. Done when the window cannot shrink below a usable
    sidebar + chat + composer width and popovers clamp to the viewport.

- [x] **The connection banner covers the first timeline row** — `S`
  - `connectionBanner` is placed at `headerY - 26` (`MainWindow+Layout.swift:499`) while the
    timeline still starts at `headerY` (`:640`), so the top 26pt of messages are hidden while
    disconnected/reconnecting. Reserve space in the timeline frame while the banner is
    visible.

- [ ] **Theme is applied once at launch and not on team switch** — `M`
  - `ThemeManager.apply` is only called in `AppDelegate.showMainWindow`
    (`AppDelegate.swift:290-295`) using the first team. `switchActiveTeam`
    (`MainWindow+Sidebar.swift:897-939`) never re-fetches preferences or re-applies the
    theme, so per-team themes need a relaunch. `preferences_changed` is not handled.
  - Done when switching teams applies that team's theme immediately and server theme
    changes apply without relaunch (or via a documented refresh).

- [x] **Avatar colors are non-deterministic and `abs(hashValue)` can trap** — `S`
  - `abs(authorName.hashValue) % palette.count` (`MainWindow+Timeline.swift:1762`) and
    `abs(user.username.hashValue) % palette.count` (`MainWindow+Menus.swift:955`) use
    randomly seeded `hashValue`, so avatar colors change every launch. `abs(Int.min)`
    traps. Derive a stable index from the user id (e.g. FNV-1a) and avoid `abs`.
  - `MMPalette.avatarColors` is computed from `Theme.shared`, so colors also shift with
    theme changes; cache or define a stable palette.

- [x] **The lightbox credits the current user instead of the poster** — `S`
  - `showLightbox` (`MainWindow+Timeline.swift:877-898`) builds the subtitle from
    `currentUser`, and callers pass no author. Viewing someone else's image says
    "You Shared In ~channel". Pass the post author (or file uploader) through.

- [x] **Status changes are optimistic with no failure feedback** — `S`
  - `selectUserStatus` (`MainWindow+People.swift:75-114`) updates the dot/menu immediately
    and only logs a failed `PUT /users/{id}/status`. Done when failure reverts the UI and
    shows an error.
  - Also in `MainWindow+People.swift:420-424`, `preloadDMUsers` writes
    `userStatusById[st.user_id] = st.status` directly without calling
    `normalizedStatus(st.status, dndEndTime: st.dnd_end_time)` or saving `dnd_end_time`.

- [x] **Copied links omit the scheme for bare hosts** — `S`
  - `copyChannelLink` (`MainWindow+Menus.swift:1112-1127`) and `copyPostLink`
    (`MainWindow+Timeline.swift:1209-1230`) concatenate `UserDefaults "host"` directly. A
    host saved as `mattermost.example.com` produces `mattermost.example.com/team/channels/x`
    instead of `https://…`. Build the URL through `WebService.buildURL` (which normalizes
    scheme/port).
  - Both helpers also drop subpaths and mishandle hosts that already contain a port
    (`https://host/mattermost`), producing broken links on reverse-proxy deployments.

---

## P2 — Security, privacy & packaging

- [x] **Unescaped URL path parameters and multipart header injection in `WebService`** — `S`
  - `fetchUserByUsername` (`webservice.swift:670`) and `removeReaction` (`:1091`) interpolate
    `username` and `emojiName` directly into the URL path without
    `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`.
  - `uploadFile` (`webservice.swift:940`) interpolates `filename` directly into
    `Content-Disposition: form-data; name="files"; filename="\(filename)"\r\n` without
    escaping `"` or `\r\n`, breaking uploads for filenames containing quotes and allowing
    multipart header injection.

- [x] **Credential-adjacent `NSLog` calls are still unconditional** — `S`
  - `AppDelegate.swift:67` logs `host:port`; `:155` logs `username@host:port`;
    `:163/:167/:173` log login outcomes/errors. These bypass the `DebugLog` gating added
    for the raw WebSocket/HTTP payloads and put account identifiers in the unified log on
    every release launch.
  - Replace with `DebugLog.info/error` (identifiers only) and keep credential values out of
    every log path. Re-audit the remaining 28 `NSLog` call sites.

- [x] **The account password is always persisted, with no "remember me"** — `M`
  - `LoginWindow` writes the password on `viewWillDisappear` (`:39-50`) and again on Connect
    (`:142-146`), regardless of user intent; `AppDelegate.startAuthentication` then uses it
    for token-less auto-login. Prefer token-only persistence with an explicit "Keep me
    signed in" option; clear the password after a successful token exchange by default.
  - `LoginWindow.viewWillAppear` reads the Keychain synchronously on the main thread
    (`:36`), reintroducing the launch stall that `AppDelegate.startAuthentication`
    deliberately avoids. Move it off-main.

- [ ] **No SSO / SAML / OAuth / MFA login** — `L`
  - `LoginWindow` only supports username+password (`LoginWindow.swift:128-176`); the login
    payload has no `mfa_token`, token-less flows, or browser-based SSO callback. Many
    Mattermost deployments require one of these. Add MFA first (simple field), then an
    external-browser SSO flow with a registered URL scheme.

- [ ] **Inline/Giphy images are fetched automatically from arbitrary remote hosts** — `M`
  - Markdown images and Giphy URLs are loaded directly with `URLSession` without auth,
    size limits, or a proxy (`MainWindow+Timeline.swift:420-463`). Any message can therefore
    leak the viewer's IP/User-Agent to a third party and fill memory/disk (caches are
    unbounded). Add a "Load images automatically" preference (off/known hosts/always),
    limit response size/type, and cap the disk cache.

- [x] **Per-user state leaks across accounts** — `S`
  - `customStatusText/Emoji` (`MainWindow.swift:208-209`, `MainWindow+People.swift:179-196`)
    and `recentEmojis` (`MainWindow+Composer.swift:45,225`) are global `UserDefaults` keys,
    never cleared on logout. A second account on the same Mac inherits the first account's
    status and emoji history. Scope them by user id/server or clear on logout.

- [ ] **Re-verify the privacy manifest against file-metadata usage** — `S`
  - `PrivacyInfo.xcprivacy` declares only `UserDefaults` CA92.1. `DebugLog.rotateIfNeeded`
    uses `FileManager.attributesOfItem` (`webservice.swift:127-136`) and the GIF cache uses
    file writes; confirm no required-reason file-timestamp API is in use (or declare it),
    and re-run the audit when the cache/download code changes.
  - Also document that messages/attachments are user data stored only in caches/temp.

- [x] **No application-level integrity/diagnostics story** — `S`
  - There is no crash reporting, no "Export diagnostics" action, and no way for users to
    inspect the gated debug log from the UI. Add a diagnostics export (redacted) and a
    feedback/report path.

---

## P3 — Web-parity backlog

### Message rendering

- [ ] **Markdown block support is incomplete** — `M`
  - `formattedMessage` uses `.inlineOnlyPreservingWhitespace`
    (`MainWindow+Timeline.swift:1961-2037`). Blockquotes are flattened to `|` prefixes,
    bullets to `•`, and numbered lists/headings/tables/horizontal rules are not rendered;
    fenced code has no language label, copy button, or syntax highlighting.
  - Add a proper block parser (or a Markdown renderer) for headings, ordered lists, tables,
    blockquote styling and fenced-code chrome. Keep the current inline pass for
    mentions/channels/emoji.
  - The inline-enhancement pass excludes only fenced code, not backtick inline-code spans
    (`MainWindow+Timeline.swift:2123-2169`), so `@user`, `~channel` and `:emoji:` inside
    inline code get styled or replaced; the channel regex also matches `#fragment` in URLs.
  - The bundled emoji catalog has ~371 entries (`MainWindowSupport.swift:159-551`), so other
    valid shortcodes render literally (`MainWindow+Timeline.swift:1272-1278`). Ship the full
    Mattermost emoji data or load it from the server.
  - Author labels are not truncated and the "Update your status" pill precedes the timestamp
    (`MainWindow+Timeline.swift:1786-1849`), so long usernames or the pill clip the time.

- [ ] **No reply count/thread indicator on timeline root posts** — `S`
  - `createPostRow` never shows "N replies" or a participant avatars row, so users cannot
    tell a root has a thread without opening the hover menu. Add the reply footer from the
    web client and refresh it on `thread_updated`/reply.

- [ ] **The 216pt welcome hero is rendered above every channel** — `S`
  - `rebuildTimelineContent` always adds `timelineHeroContainer` and advances by 216 + 16pt
    before the first post (`MainWindow+Timeline.swift:2230-2239`). Every channel therefore
    starts with a large intro illustration even when it has history, pushing messages down
    and changing scroll geometry. Show it only for empty/new channels (or as a compact
    start-of-history marker).

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

- [ ] **No Save/Flag post action** — `S`
  - The hover menu has only Reply, Copy Link, Pin/Unpin and Delete
    (`MainWindow+Timeline.swift:1125-1144`), yet a Saved Posts panel exists. Add
    Save/Unsave (Mattermost `POST/DELETE /users/{id}/posts/{post_id}/flag`), plus
    Edit/Copy Text/Mark Unread. Currently only the ↑ shortcut can start an edit, and pin is
    restricted to own posts.

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

- [ ] **The fallback sidebar uses fake IDs and skips unread badges** — `S`
  - When the categories response is empty, `populateSidebarCategories` returns through
    `buildDefaultSidebarCategories()` before `loadUnreadState()` (`MainWindow+Sidebar.swift:421-424,550`),
    so badges never load. The fallback rows use hardcoded `"town-square"`, `"off-topic"`,
    `"system-bot"` IDs (`:310-323`) that do not match real server IDs, so selection and
    unread lookup are wrong. Build the fallback from real channels.

- [ ] **"View Info" opens the Members panel instead of channel info** — `S`
  - `MainWindow+Menus.swift:1030-1033` maps View Info to `.members`. Channel header,
    purpose, creator, created date, member count, files/pins shortcuts and notification
    preferences are not shown. Add a Channel Info RHS mode.

- [ ] **Profile is a no-op; there is no user profile view** — `M`
  - The status menu's Profile row (`MainWindow+Menus.swift:487-506`) does nothing. There is
    no profile popover/sheet (avatar, title, timezone, local time, status, DM button), and
    member rows are not clickable (`MainWindow+RightPanel.swift:368-373`).
  - Add a profile view reused by members, mentions, search authors and the current user;
    add "Message" and "Copy username".

- [ ] **Status/Help/Product menus have dead rows and hardcoded chrome** — `S`
  - `setupStatusMenu` (`MainWindow+Menus.swift:315-318`) hardcodes the menu avatar color,
    never loads the user's actual avatar image, falls back to hardcoded `"boris"`, and never
    updates `@username` or initial after `fetchCurrentUser()` completes if `UserDefaults`
    was empty or changed.
  - `dndSubMenu`'s "Choose date and time" row (`MainWindow+Menus.swift:586,617-632`) has
    `durationSeconds: nil` and no picker handler, so clicking it silently enables indefinite
    DND instead of opening a date/time picker.
  - All rows in `helpMenu` (`MainWindow+Menus.swift:261-283`) and `productSwitcherMenu`
    (`:156-178`) only close the menu on click (`:694-698`) and perform no action.
  - `editionBadgeLabel` (`MainWindow.swift:29`) and the product switcher footer
    (`MainWindow+Menus.swift:192-238`) hardcode `"TEAM EDITION"` / `"free unsupported edition"`
    instead of reading the server's actual license/config.
  - The `"Update your status"` pill (`MainWindow+Timeline.swift:1801-1837`) is shown on every
    non-consecutive message by the current user even when a custom status is already set.

### Composer and account

- [ ] **Formatting toolbar is visual only** — `M`
  - The nine `composerLeftButtons` (`MainWindow+Layout.swift:304-334`) have hover styling
    but no `onClick`; the `Aa` toggle only shows/hides them. Wire Bold/Italic/Strike/
    Heading/Link/Code/Quote/Lists to wrap the selection in Markdown (and update
    `entryView` styling). This is also a README overclaim.

- [ ] **GIF search is absent while a local fake-post path remains** — `S`
  - `applyComposerToolbarVisibility` always hides the GIF button
    (`MainWindow+Composer.swift:803`), but its old handler still fabricates a
    `giphy_*` post locally and appends it to the timeline (`MainWindow+Layout.swift:414-429`).
    Remove the dead mock, and if the server has a Giphy plugin (check
    `GET /plugins`), add real search/attach through the plugin endpoints.

- [ ] **Login window UX is incomplete** — `M`
  - Fixed frames (`LoginWindow.swift:68-106`) do not reflow on resize and there is no
    minimum size; there is no spinner/"Connecting…" state, no show-password toggle, no
    server-discovery-by-email, and errors remain while the user edits. Add Auto Layout, a
    progress state, validation, and a clear error area.

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

- [ ] **No standard app menus / Preferences / reopen behavior** — `S`
  - `setupMainMenu` (`AppDelegate.swift:372-454`) omits Services, Hide, Preferences (⌘,),
    a Help menu and standard About metadata. Add a Settings scene/window (or ⌘, sheet) and
    `applicationShouldHandleReopen`.

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

- [ ] **GIF cache filenames use randomized `hashValue`** — `S`
  - Long URLs are cached as `"\(urlString.hashValue).gif"` (`MainWindow+Timeline.swift:353-356,430-432`).
    Swift hash seeds change per process, so the on-disk cache misses every launch and
    duplicate files accumulate; collisions can serve the wrong image. Use a stable hash
    (SHA-256 or FNV-1a) and add cache eviction.

- [ ] **Timeline pagination can drop edits and refetch the same page** — `S`
  - `TimelinePager.merge` filters duplicate IDs out of the older page
    (`TimelineSupport.swift:21-30`), so an edited duplicate keeps the stale copy; sorting by
    `create_at` alone is unstable for equal timestamps and can flip grouping. In
    `MainWindow+LiveData.swift:493-496`, a full page containing only duplicates returns
    without setting `didLoadAllHistory`, so repeated bounds changes refetch it.
  - Older-page scroll anchoring is skipped when `anchorOffset == 0`
    (`MainWindow+LiveData.swift:511-515`), so loading at the exact top replaces the viewport
    instead of preserving the oldest visible post.

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

- [ ] **Docs are stale/overclaiming** — `S`
  - `AUDIT.md` says 48/48 tests in the verification table but 51 later, and its reported
    14,892 Swift lines is stale (the current app plus test sources total 15,053). `README.md` advertises a Files tab in the search popover that does
    nothing, and the GIF mock cleanup is not actually complete.
  - Update both after each release; add a "Known limitations" section for DND/mute, search
    Files tab, threads and accessibility.

- [ ] **No reproducible Release checklist** — `S`
  - Document: bump/tag, clean build, test, lint, Release build, universal check, sign,
    notarize, staple, `spctl` verify, DMG checksum, clean-machine launch. Add a
    `Makefile`/script target so the steps cannot drift.

---

## Suggested next 14 (highest value first)

1. **Fix `hitTest` on icon-only custom controls** — image icons currently swallow clicks.
2. **Drafts + optimistic send/retry** — stops data loss and wrong-channel sends.
3. **Realtime edit/delete/read events** — the largest correctness gap versus web.
4. **Filter thread replies out of the channel feed** — replies currently appear inline.
5. **Sidebar scroll + Favorites filter + per-team isolation** — broken navigation/data leak.
6. **RHS reflow** — panels currently cover messages instead of shrinking the center column.
7. **DND units / custom-status duration + mute/notification prefs** — status/notification bugs.
8. **Search Files tab + result jump** — two visible dead ends.
9. **Attachment save entitlement + upload progress/size checks** — data integrity.
10. **Thread read state + rich reply composer + RHS pagination** — daily-use gaps.
11. **Logout state cleanup + remove credential `NSLog`s** — security/privacy hygiene.
12. **Sign, harden, notarize and add a Release CI job** — unblocks distribution.
13. **Accessibility pass** (labels, focus, keyboard activation) — required for real users.
14. **Timeline incremental updates + image caching** — before channels get large.

---

## Completed baseline

The following were verified as implemented at this revision and should not regress. Detailed
history is in git; the original long-form checklist lives in prior commits of this file.

- **Composer:** editable editor, Return/Shift-Return, send/edit via ↑, delete, typing events,
  insertion after a successful send (a true optimistic insert is still P1), emoji picker with
  categories/search/recents/custom emoji, `@`/`#`/`:emoji:` autocomplete, file attach +
  drag-and-drop, attachment chips, formatting-toolbar chrome, ⌘K/⌘F, Esc overlay handling,
  focus traversal.
- **Search:** real global search field, `POST /teams/{team}/posts/search`, floating results
  with click-to-open, Messages/Files tab styling, scoped `in:` prefill from ⌘F.
- **RHS:** Threads, Members, Pinned, Files, Mentions, Saved, Settings, Browse Channels, thread
  view with grouped replies + inline reply, draggable/persisted width, channel subtitle.
- **Timeline:** 60-post `before` pagination with viewport anchoring, per-channel unread
  badges, mentions, "New Messages" divider + floating jump pill, date separators with
  localized relative labels, 5-minute grouping, edit/delete tombstones, pinned markers,
  attachments/image cards/lightbox, reactions chips with add/remove, hover toolbar, inline
  markdown/code/mentions/channels/emoji/images, Giphy rendering.
- **Realtime:** WebSocket posts, presence, typing, reaction refresh, exponential-backoff
  reconnect, wake/network reconnect, connection banner, 15 s status backstop.
- **Sidebar/teams:** server categories, favorites persisted as user preferences, unread/
  mention state from memberships, live Find channel filter, add/browse/join channels, invite
  email, create team + switch, DM creation, channel menu (info/pins/files/favorite/copy/
  leave).
- **Status:** custom status with duration, DND expiry normalization, status menu/checkmarks,
  server-backed presence. (Two regressions are tracked in P1: `dnd_end_time` units and the
  invalid `dont_clear` duration.)
- **Themes:** Denim/Sapphire/Quartz/Indigo/Onyx + custom palettes, dark detection, app-wide
  application, design tokens for radii/metrics/native accents.
- **Security/packaging:** Keychain in Release (documented debug plaintext store), HTTPS/443
  default with local-network ATS exception, scoped privacy manifest, correct icon set,
  gated payload logging, macOS 14 deployment target, notarization still open (P0).
- **Architecture:** `MainWindow` split into focused extensions, `ChatViewModel`, injected
  `WebService`, `@MainActor` + Swift 6 complete concurrency, deduplicated HTTP request
  building, dead prototype removal, centralized tokens.
- **Tooling/tests:** 51 unit tests across URL/JSON/WS/model/timeline/zoom/errors/logging/
  themes, CI build+test+lint, `swift-format` config, HUD measurement helper under
  `tools/hud_measure.swift`.

---

## How to verify changes

```bash
./build.sh      # must succeed with no new warnings
./test.sh       # 51 tests today; keep the count rising
./lint.sh       # swift-format --strict on the migrated allowlist
./run.sh        # manual smoke test
```

Smoke checklist for any change: launch → token restore → switch channels/teams → type a
draft in A, switch to B and confirm it does not follow → scroll history while a message
arrives → send/edit/delete → react/pin/save → open Threads/Members/Files/Mentions/Saved →
upload and download a file → set DND and confirm notifications stop → zoom (⌘0/⌘+/⌘−, pinch,
HUD) → resize/relaunch (frame + RHS width restore) → log out and back in (no state leakage).
