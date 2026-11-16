# TODO — `mattermost.client`

_Reviewed: 2026-11-15 · Revision: `e74d2ee` (tag `0.8.0` + fixes) · Scope: 26 application Swift files (15,617 lines),
8 unit-test files (1,049 lines), `RELEASE.md`, `tools/hud_measure.swift`, Xcode project,
build/release scripts, CI, README/AUDIT._

**Verified baseline at this revision**

| Check | Result |
|---|---|
| `./build.sh` | **Succeeds**, 0 compiler warnings |
| `./test.sh` | **287/287 pass** (coverage ≥ 50%) |
| `./lint.sh` | **Passes** (`swift-format --strict` across all source files) |
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

---

## P5 — Quality, tooling & documentation

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
