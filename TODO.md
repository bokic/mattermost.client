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
  - Remaining: "mark all as read" (`PUT /users/{id}/teams/{team}/read`) and mute-based suppression.

- [x] **Post model cannot represent attachments, reactions, pinned posts, edits or deletes** — `M`
  - Done: `MMPost` decodes `metadata.files`/`metadata.reactions` and `file_ids`. The timeline renders
    image previews (`/files/{id}/preview`) and file chips (name + size, click opens the download),
    grouped reaction chips with shortcode→glyph mapping, a gold pin on pinned posts, the ✎ Edited
    indicator, and a "This message was deleted." tombstone for `delete_at > 0`.
  - Also fixed consecutive grouping to break after five minutes, and attachments/reactions on
    grouped (consecutive) rows.
  - Remaining: interactive reactions (add/remove), file thumbnails beyond the preview endpoint, and
    `props`-driven custom attributes.

- [x] **Custom status is inert; DND expiry is not refreshed** — `S`
  - Done: the status menu opens a custom-status sheet (emoji, text, duration: don't clear / 30m / 1h /
    4h / today / this week) that calls `PUT /users/me/status/custom` with the server's duration enum
    and an RFC3339 `expires_at`; Clear calls DELETE. The current status is shown in the menu row and
    persisted locally.
  - DND expiry: `dnd_end_time` is cached per user from REST responses, and both REST and WebSocket
    status updates normalize expired DND to online — updating the header dot, menu checkmarks and
    timeline presence dots. The 15 s status poll acts as a backstop.
  - Remaining: custom status isn't re-fetched on launch (the server exposes no GET endpoint), so it
    is restored from local storage.

- [x] **Sample posts are injected when logged out** — `S`  
  _Done: demo content only renders with an explicit `--demo` flag._
  - Where: `rebuildTimelineContent` (≈3827) fabricates "sarah.connor" posts when not logged in.
  - Done when: demo content is behind an explicit `--demo` flag or removed.

- [x] **Message rendering gaps** — `M`
  - Done: fenced code blocks and inline code render monospaced on a tinted background; `@mentions`
    get the blue highlight; `~channel`/`#channel` links are styled and open the channel in-app;
    `:emoji:` shortcodes expand to glyphs; Markdown images (png/jpg/jpeg/gif/webp/bmp and Giphy) are
    extracted and rendered as inline images. External links still open in the default browser.
  - Remaining: Markdown tables and syntax highlighting inside code blocks.

- [x] **WebSocket reconnect is a fixed 3 s retry** — `S`
  - Done: exponential backoff with jitter (1 s → 30 s cap), reset on a successful `hello`, and
    immediate reconnect on `NSWorkspace.didWakeNotification`.
  - Visible state: a slim amber banner ("Connecting…", "Reconnecting to Mattermost…", "Disconnected
    from Mattermost") appears below the channel header while the socket is down and hides on connect;
    the Settings panel's Reconnect row shows Connected/Reconnecting.

- [x] **Typing is receive-only; date/time handling is static** — `S`
  - Typing: `sendTypingIfNeeded()` already fires from the composer's text-change delegate (throttled to
    1.5 s) via `user_typing`; receive-side indicators were already wired.
  - Dates: every formatter now uses `Locale.current` — timestamps are `timeStyle = .short` (respects
    24-hour settings), date separators use relative Today/Yesterday (`doesRelativeDateFormatting`),
    localized weekday names and the localized medium date; search results, mentions, saved/pinned
    rows, the edited tooltip and the DND "Tomorrow" label all use the same helpers. The hardcoded
    `en_US_POSIX` formatters are gone.

---

## P2 — Security, privacy & packaging

- [x] **Credentials are stored in plaintext `UserDefaults`** — `M`
  - Done: release builds use `SecItemAdd`/`SecItemUpdate`/`SecItemCopyMatching`/
    `SecItemDelete` with `kSecClassGenericPassword`, a service scoped to the app and
    `kSecAttrAccessibleAfterFirstUnlock`.
  - Debug builds (`#if DEBUG`, enabled via `SWIFT_ACTIVE_COMPILATION_CONDITIONS`) intentionally use
    a plaintext UserDefaults store (`debugCredential.*`) instead of the Keychain. Rebuilding an
    ad-hoc/development-signed app changes its code signature, which makes macOS prompt for the
    login-keychain password on every launch; the debug store keeps the edit/build/run loop prompt-free
    and is compiled out of release builds.
  - Legacy `auth_token`/`auth_password` (and un-prefixed) UserDefaults values are migrated on first
    read and deleted at launch via `migrateLegacyCredentials()`. Release builds also purge any
    `debugCredential.*` values left by a debug build.
  - Verified: launch logs which store is active; debug builds sign in without any Keychain prompt,
    while release builds use the Keychain.

- [x] **Cleartext HTTP by default and no ATS configuration** — `S`
  - Done: plain hostnames now resolve over `https` with the scheme default port (443); `http://`
    must be typed explicitly and is limited to local networks.
  - The app ships a scoped ATS exception (`NSAllowsLocalNetworking`) via `Config/Info.plist`, merged
    with the generated Info.plist — public cleartext hosts stay blocked.
  - The login port field is optional (443/80 defaults), unsupported schemes are rejected, and a
    port embedded in the host wins over the port field. URL tests updated (16 total).

- [x] **Deployment target contradicts README** — `S`
  - Done: `MACOSX_DEPLOYMENT_TARGET = 14.0` is set at the project level, so both the app and the test
    target inherit it. The built bundle now reports `LSMinimumSystemVersion = 14.0` and the binary's
    `LC_BUILD_VERSION.minos` is 14.0.
  - The full build compiles against the 14.0 target with no availability or deprecation warnings.
  - Caveat: not yet smoke-tested on an actual macOS 14 machine (only the 27.x host is available).

- [x] **App icons are the wrong size** — `S`
  - Done: rebuilt the icon set from the largest artwork (trimmed to its 512×512 opaque bounds and
    upscaled to a 1024 master), then generated every slot from that master.
  - All ten PNGs are now square and match their declared point/scale (16, 32, 32, 64, 128, 256, 256,
    512, 512, 1024). `assetutil` shows matching renditions in `Assets.car` and the system icon
    resolves up to 1024×1024.
  - Follow-up: Finder still showed a generic icon because IconServices rejects icons containing
    transparent pixels on current macOS. The artwork is now flattened onto its background blue as a
    full-bleed opaque square, and the system applies the squircle mask — Finder and the Dock render
    the compass correctly.

- [x] **No privacy manifest** — `S`
  - Done: added `mattermost.client/PrivacyInfo.xcprivacy` (picked up by the synchronized target
    group and copied to `Contents/Resources/`). It declares `NSPrivacyTracking = false`, no
    collected data, no tracking domains, and the only required-reason API in use —
    `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (app's own preferences).
  - Audited the other required-reason categories (file timestamps, system boot time, disk space,
    active keyboard); none are used.

- [x] **Raw WebSocket payloads are written to the system log** — `S`
  - Done: removed the raw `NSLog` calls that printed every frame. Payload-bearing logs (WS
    RECV/SEND frames, dispatch event dumps, HTTP request/response bodies, MainWindow's event mirror)
    now go through `DebugLog.logSensitive`, which is disabled unless launched with `--debug-ws` or
    `debugWebSocketLogging = true` in defaults. The autoclosure means the payload isn't even
    formatted when logging is off.
  - Remaining diagnostic logs contain only identifiers, state transitions and error descriptions.
  - Verified with a new `DebugLogTests` case: the marker string is absent when gated and present when
    enabled (17 tests total).
  - Related fix: Keychain reads moved off the main thread at launch, so a pending Keychain
    authorization prompt can no longer stall `applicationDidFinishLaunching`.

---

## P3 — Web-parity backlog

- [x] **Post hover toolbar** (emoji/reply/more) and reaction chips — `M`
  - Done: every post row reveals a hover toolbar at its top-right, matching `ul.post-menu` in
    the web client — 38pt tall, white, 1pt `rgba(63,67,80,0.2)` border, 4pt radius, three 28pt
    icon buttons (emoji, reply, more) with 64%-opacity icons that darken to 80% and get an 8%
    hover fill. Compact (grouped) rows use a 24pt-tall variant so the toolbar stays inside the
    row. System and deleted posts get no toolbar.
  - Emoji opens a reaction picker anchored to the button; reply opens a thread view in the right
    sidebar; more opens a menu with Reply, Copy Link, Pin/Unpin and Delete (own posts only).
  - Reaction chips now mirror `.Reaction`: 24pt tall, 4pt radius, 1pt border, 0/5pt padding,
    4pt gap, 16pt emoji, 11pt semibold count. Own reactions use the button blue border and 8%
    blue fill; unreacted chips hover to white with a 16% border. Reaction chips are clickable and
    toggle via `POST /reactions` / `DELETE /users/{u}/posts/{p}/reactions/{emoji}`.
  - Added a matching `+` add-reaction chip (revealed on row hover) and a reaction picker with
    16 common emoji.
  - The thread view reuses the timeline row renderer: root post, "N replies" divider, grouped
    replies, and an inline "Reply to thread…" composer that posts with `root_id`. Opening a reply
    normalises the target to the thread's root.
  - Realtime: `reaction_added` / `reaction_removed` WebSocket events (including the stringified
    `data.reaction` payload) refresh the affected post.
  - Verified by an in-app harness (synthetic clicks are blocked in the locked desktop session):
    reaction add → remove → restore, thread load, and reply count 2 → 3. Added WebSocket reaction
    parsing and endpoint URL tests (19 tests pass).
- [x] **Attachments and inline images** with correct web sizing, thumbnail previews and lightbox — `M`
  - Image attachments now match `.file-view--single`: natural size capped at 700pt wide and 350pt
    tall, 8pt radius, 1pt `rgba(63,67,80,0.16)` border, with a hover download button. Preview data
    comes from `/files/{id}/preview`; the full file is loaded for the lightbox.
  - File attachments now render as `.post-image__column` cards: 320×64pt white card, 4pt radius,
    1pt border, 63pt blue file-type thumbnail, 12pt semibold name, `TYPE SIZE` (e.g. `TXT 20B`) and
    a 32pt download button. Multiple cards flow horizontally and wrap at the post width.
  - Inline markdown/Giphy images use the web inline metrics: natural size, 100% max width, 350pt max
    height, 4pt radius, no upscaling. Pixel dimensions are read from image reps (not `NSImage.size`,
    which is in points) and cached so the timeline reflows once to the real aspect ratio.
  - Added the full-screen lightbox: 72pt black header (40pt avatar, 16pt filename, author +
    `Shared In ~channel`, download and close actions), 40pt translucent zoom bar with −/fit/+,
    and a 90% black stage with a 48pt padded, 8pt-radius image centred at fit size. `Esc` or a
    click on the backdrop closes it; the download action saves the file (or remote image) via a
    save panel; the overlay follows window resize/zoom.
  - Verified against computed styles from the live web client and screenshots of the timeline and
    lightbox; 19 tests pass.
- [x] **"New Messages" divider and unread pill** above the first unread post — `S`
  - Done: the divider now matches `.NotificationSeparator` from the web client — a 1pt rule in
    `rgba(255,136,0,0.5)` behind a white 26pt pill with 13pt regular `#ff8800` text and 13pt
    horizontal padding. It is inserted immediately above the first post newer than the channel's
    `last_viewed_at`.
  - Opening a channel with unread messages now scrolls to the divider instead of the bottom.
  - Added the web's floating jump pill: when the divider is below the viewport, a 32pt blue
    (`#1c58d9`) 4pt-radius bar with a down arrow and "N new messages" (13pt bold white) floats
    above the composer; clicking it scrolls to the divider. It hides when the divider is visible.
  - Scrolling past the divider hides and retires it (once the user has actually scrolled with the
    wheel/trackpad), matching the web client's collapse behaviour. A programmatic scroll on open
    does not collapse it.
  - Verified with a temporary demo harness: divider styling, pill text/positioning and the
    collapse state transition; temporary hooks were removed. 21 tests pass.
- [x] **Right-hand sidebar** (threads, members, pinned posts, files) with resize/persist — `L`
  - Done: the right-hand panel now covers Threads, Members, Pinned Posts, Files, Recent Mentions,
    Saved Posts, Settings and Browse Channels, all rendered in the same 400pt default panel.
  - Added the Files view using the web client's channel-file search
    (`POST /teams/{team}/files/search` with `terms=channel:{id}`). Rows mirror
    `.FileSearchResultItem`: 64pt bordered cards, 40pt image/file thumbnail, 12pt semibold name and
    `size • Today at 1:33` metadata; clicking an image opens the lightbox, other files open/download.
  - Header now matches the web: 56pt tall, 16pt semibold title, 12pt 75% channel subtitle to the
    right, and a 32pt close button.
  - Added a draggable 6pt resize handle on the left edge (resize-left-right cursor, hover highlight)
    with a 280–(chat − 360) clamp. The width persists in `UserDefaults` under `rhsWidth` and is
    restored at launch; releasing the drag reflows the active panel.
  - Added a Files button to the channel header and a Files item to the channel menu.
  - Verified against computed styles from the live web client and screenshots of the Files view at
    400pt and after resizing to 480pt; `rhsWidth` was persisted and restored. 22 tests pass.
- [x] **Saved posts / mentions / settings / invite / channel browser / DM creation** — `M` each
  - Saved posts and Recent Mentions are server-backed RHS lists (`GET /users/{id}/posts/flagged`
    and post search with `@username`). Both now jump to the exact post: the channel opens, the
    target post is fetched directly with `GET /posts/{post_id}` when it is outside the latest page,
    and the row scrolls into view with a short blue highlight.
  - Settings remains the gear panel with Reset zoom, Reconnect, Account/server details and Log out.
  - Invite Members (sidebar row and welcome hero) sends a real team email invite through
    `POST /teams/{team}/invite/email`, with email validation and success/error feedback.
  - Browse Channels lists public team channels, marks joined channels, joins on click through
    `POST /channels/{id}/members`, and refreshes the sidebar categories afterwards.
  - Direct Message creation: the `+` in the DIRECT MESSAGES header now opens a searchable user
    picker (`GET /users?in_team=…`); choosing a user creates or reuses the DM with
    `POST /channels/direct`, adds the user to the directory, refreshes categories, and opens the
    conversation. The picker closes on outside click, the anchor button, or `Esc`.
  - Also fixed the welcome hero description to wrap instead of truncating long DM intros.
  - Verified DM creation end-to-end against the live server (test1234) and the picker/search UI;
    22 tests pass.
- [x] **Emoji picker** (server emoji list + recent) — `M`
  - Replaced the fixed 40-emoji palette with a web-metric picker: 350×440pt white panel,
    4pt radius, 1pt `rgba(63,67,80,0.2)` border and an `0 8px 24px` shadow.
  - Added a search field and a category bar with Recent plus Smileys & Emotion, People & Body,
    Animals & Nature, Food & Drink, Travel & Places, Activities, Objects, Symbols and Flags.
    Categories render as 9×36pt grids with 36pt cells, 12pt uppercase headers and the web's
    blue-selected / 64%-gray idle category styling.
  - Recent emojis are stored in `UserDefaults` (`recentEmojis`, newest first, max 18) and appear
    as the first category once something has been selected.
  - Custom server emoji are loaded from `GET /api/v4/emoji` and their images from
    `/api/v4/emoji/{id}/image`; they appear in a Custom category and insert `:name:` shortcodes.
    Custom emoji now render as 18pt inline attachments in message bodies.
  - Search filters all standard and custom emoji by shortcode; the selected emoji is inserted into
    the composer and recorded as recent, and the panel closes.
  - Verified with screenshots of the Smileys, People, Recent and search states. This server has no
    custom emoji, so the Custom category is hidden until the API returns results. 23 tests pass.
- [x] **Server theme support** (read `preferences` theme, custom colors, dark mode) — `M`
  - Reads the `theme` user preference (`GET /users/{id}/preferences`), preferring the active team's
    entry and falling back to the global (`name == ""`) entry. Fetched before the main window is
    created, so the UI starts in the server theme; no preference defaults to Denim.
  - Supports the built-in Mattermost palettes (Denim, Sapphire, Quartz, Indigo, Onyx) plus custom
    themes by parsing `sidebarBg`, `sidebarText`, `sidebarTextHoverBg`, `sidebarTextActiveBorder`,
    `sidebarHeaderBg`, `sidebarTeamBarBg`, `centerChannelBg`, `centerChannelColor`, `linkColor`,
    `buttonBg`/`buttonColor`, `mention*`, `newMessageSeparator`, indicators and error colors. Dark
    mode is detected from the center-channel background luminance.
  - Applied the palette across the window/top bar/sidebar, message timeline, composer, date and
    "New Messages" separators, hover toolbars, reactions, attachment cards, right-hand panel,
    Files/Threads rows, search/menus/popovers, emoji picker and DM picker. Derived hover, divider,
    muted and placeholder colors are blended from the center-channel palette so dark themes get
    proper layering. Emoji/DM search fields switch between aqua and dark aqua.
  - Verified with screenshots in Onyx (dark), Quartz (light sidebar with dark text) and the default
    Denim theme, plus preference-selection and custom-color unit tests. Theme changes made on the
    server apply on the next launch. 26 tests pass.
- [x] **Keyboard shortcuts**: ⌘K search, ⌘F in-channel search, `Esc` to close overlays, `↑` to edit
      last message, focus traversal between sidebar/timeline/composer — `M`
  - Added Search (⌘K) and Find in Channel (⌘F) to the Edit menu and to `performKeyEquivalent`.
    ⌘K opens/focuses the global search popover; ⌘F prefills `in:<channel-name> ` and places the
    caret at the end so typing continues the scoped search.
  - `Esc` now closes the topmost overlay in order — lightbox, DM picker, emoji picker, reaction/post
    menus, channel/product/help/status/team/filter menus, search popover/results, right panel — and
    cancels composer editing when nothing else is open.
  - Pressing `↑` in an empty composer loads the current user's last post into the composer for
    editing (help label shows `Editing • Esc to cancel`). Enter saves through
    `PUT /api/v4/posts/{id}/patch`, updates the timeline/thread in place, and Esc restores the
    composer. Switching channels cancels an in-progress edit.
  - `Tab` / `Shift+Tab` cycles focus composer → sidebar → timeline (sidebar focuses Find channel;
    the timeline container forwards arrow keys to the scroll view). Search/DM/emoji fields keep
    their normal Tab behaviour.
  - Verified with an in-app harness: ⌘F produced `in:town-square `, ↑ loaded the last message,
    Esc cancelled it, and the focus cycle logged composer → sidebar → timeline → composer.
    27 tests pass.
- [x] **Drag & drop files** onto the composer — `M`
  - The composer text view and its outline panel are file-URL drag destinations; dragging over
    either highlights the composer border in the theme's button color and shows
    "Drop files to attach".
  - Dropped files (and the attach button) upload to the current channel and appear as pending
    attachment chips above the editor, each with a remove button. The composer grows by 36pt while
    attachments are pending and the timeline stays scrolled to the bottom.
  - Send includes the pending `file_ids`; text is optional when files are attached. On success the
    tray clears and the composer shrinks. Switching channels clears pending attachments. File reads
    use security-scoped access for Finder drops.
  - Attach now stages files in the draft instead of sending immediately, matching the web client.
  - Verified with an in-app harness: one uploaded file added a 36pt tray, the composer height became
    86, sending created a post with one file, the pending list cleared, and the test post was
    deleted afterwards. 27 tests pass.
- [x] **Mentions/autocomplete** for `@user`, `#channel`, `:emoji:` while typing — `L`
  - The composer detects `@`, `#`/`~` and `:query` tokens immediately before the caret (guarding
    against emails, URLs and times) and shows a 300pt autocomplete panel above the composer.
  - Users come from a cached `GET /users?in_team=...` list (with an immediate local fallback);
    channels are filtered from the loaded channel directory; emoji combine the bundled catalog and
    server custom emoji. Matches are prefix-ranked, capped at 8 rows.
  - Rows show avatars/initials for users, `#` + channel name/subtitle, or glyph + `:shortcode:`.
    Selecting inserts `@username `, `#channel-name ` or `:shortcode: `; emoji selections also update
    the persisted recent emoji list.
  - Keyboard: Up/Down move the selection, Enter or Tab accepts, Esc dismisses; Tab focus traversal is
    suspended while the panel is open. Clicking a row accepts, clicking elsewhere closes.
  - Verified with screenshots for users (`@bo` → @boris), channels (`#` → ch2/off-topic/town-square/zz)
    and emoji (`:sm` → smile/smiley/…), plus selection and acceptance harness logs. 27 tests pass.

---

## P4 — Architecture & maintainability

- [x] **Split `MainWindow.swift` into view components plus a view model** — `L`
  - `MainWindow.swift` is now an 867-line window shell (stored view state, init, AppKit overrides).
    The former ~10,400-line class is split into `MainWindow+Header`, `+Sidebar`, `+Timeline`,
    `+Composer`, `+Menus`, `+RightPanel`, `+People`, `+Layout` and `+LiveData` extensions, with the
    shared drag/scroll/timeline helpers and the emoji catalog in `MainWindowSupport.swift`.
  - Added `ChatViewModel`, which owns the live workspace state: current user/team/channel, channel
    and user directories, statuses, posts, pagination flags, memberships/read state, thread data and
    the WebSocket connection flag. `MainWindow` exposes internal forwarding properties so the view
    components read/write the model without duplicating storage. `MainWindow+LiveData` remains the
    controller glue that drives the REST/WebSocket service and mutates the model as events arrive.
  - Widened member access from file-private to internal so extensions can live in separate files;
    no behavior was intentionally changed.
  - Verified: the app builds and runs against the live server, all 27 unit tests pass, and the
    normal workspace view renders unchanged.
- [x] **Extract shared window/zoom plumbing** — `M`
  - Added `WindowZoomController`, used by both `MainWindow` and `LoginWindow`. It owns the
    `contentView.bounds` rewrite, observes `NSWindow.didResizeNotification` and
    `.zoomFactorDidChange`, applies the current factor, calls the owner's layout closure, shows the
    zoom HUD and handles ⌘+/⌘=/⌘-/⌘0.
  - Removed the duplicated `applyZoomFactor`/`windowDidResize`/`zoomDidChangeNotification` methods
    and observers from both window classes; only the controller rewrites bounds now.
  - Documented the scaling model in `WindowZoomController.swift`: the OS display scale is separate;
    the window frame stays in points while contentView `bounds = frame / zoomFactor`, so logical
    layout points map to `zoomFactor` screen points. Layout code consumes `bounds.size`.
  - Verified at 125% zoom: the full workspace reflows correctly, then reset to 100%. Build and all
    27 tests pass.
- [x] **Actor-isolate `WebService` and enable Swift 6 strict concurrency** — `M`
  - `WebService` is now `@MainActor`: the bearer token, host/port, socket task, sequence counter,
    ping/reconnect timers, connection flag and all event callbacks are main-actor isolated.
    URLSession still performs network I/O off the main thread; receive/ping callbacks hop back with
    `Task { @MainActor in … }` and the socket receive loop is `nonisolated` while taking the task as a
    parameter, so no non-Sendable WebService state crosses a concurrency boundary. Stale callbacks
    are ignored by comparing the task identity.
  - Marked the remaining UI singletons/helpers `@MainActor` (`AppDelegate`, `ZoomManager`,
    `ZoomHUD`, `WindowZoomController`, `Theme`/`ThemeManager`, `MMFont`) and used
    `MainActor.assumeIsolated` inside main-run-loop `Timer` callbacks. `WindowZoomController`'s
    observer tokens are `nonisolated(unsafe)` so `deinit` can release them.
  - `DebugLog.isSensitiveLoggingEnabled` is now lock-protected (`OSAllocatedUnfairLock`) instead of
    nonisolated mutable global state, so tests can still flip it.
  - Enabled Swift 6 language mode and `SWIFT_STRICT_CONCURRENCY = complete` for both targets in the
    Xcode project, and marked the XCTest classes `@MainActor`. A clean build now has zero
    concurrency warnings or errors.
  - Verified against the live server: login/session restore, workspace render, WebSocket connect and
    a realtime post all work; all 27 tests pass.
- [x] **Inject `WebService`** instead of repeated `NSApp.delegate as? AppDelegate` lookups. — `M`
  - `MainWindow` now exposes `webService` backed by `ChatViewModel.webService`. `AppDelegate`
    injects the service once via `mainWindow.start(with: webService)` instead of `MainWindow`
    reaching through `NSApp.delegate` during init.
  - Replaced the ~70 `(NSApp.delegate as? AppDelegate)?.webService` lookups across the window
    components with the injected property. The remaining delegate lookups are for non-WebService
    AppDelegate actions (`logout`, `markChannelRead`) and the login window's service handoff.
  - Removed the `bindWebServiceAndLoadData()` call from `MainWindow.init`; `start(with:)` sets the
    service and then binds WebSocket/REST callbacks and loads data, keeping the previous ordering
    before `connectWebSocket()`.
  - Verified session restore, workspace render, WebSocket connection and a full token-less launch
    (stored-password login → injected service → live workspace); all 27 tests pass.
- [x] **Remove dead/legacy code** — `S`
  - Deleted the unused `NSOutlineView` sidebar (`treeView`, `mainTreeDelegate`, `MainWindowDelegate`),
    the hidden `sidebarTopBorder` and its init/layout code, the `dateSep1/2*` prototype divider views,
    `systemMessageRow`/`userMessageRow`, `statusPromptLabelRef`/`statusPromptIconRef`, and the
    `sysAuthorLabelRef`/`usr*Ref` leftovers.
  - Kept `entryView` — it is the live `ComposerTextView` used by send/edit/autocomplete, not dead
    code. Kept `appendRealtimePost`, which still performs the optimistic realtime insert and user
    hydration on the WebSocket path.
  - Verified the workspace renders unchanged; build is clean and all 27 tests pass.
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
