# Mattermost macOS Client (`mattermost.client`)

A native macOS desktop client for [Mattermost](https://mattermost.com/) built with Swift and AppKit. It pairs a pixel-accurate reproduction of the modern Mattermost web workspace interface with native macOS performance, status bar integration, and live Mattermost REST API v4 / WebSocket synchronization.

---

## Highlights & Features

### 1. Top Global Header Bar (`#192A4D`)
- **Product Switcher**: Custom grid app switcher (`E82F`) and Mattermost logo with `TEAM EDITION` badge, opening an interactive menu (*Channels*, *System Console*, *Integrations*, *App Marketplace*, *Download Apps*, *About Mattermost*).
- **Search Popover**: Centered search bar with quick popover offering *Messages* / *Files* tabs, bordered search input, and filter hint pills (`from:`, `in:`, `on:`).
- **Help Menu**: Quick help (`?`) popup menu linking to Mattermost guides, resources, and shortcuts.
- **User Status & Profile**: User avatar with presence dot and dropdown menu (*@username*, custom status editor with emoji/text/expiry — shown in the menu, *Online*, *Away*, *Do not disturb* with *Clear after:* submenu, *Offline*, *Profile*, *Log out*). Expired DND automatically reverts to online.
- **Action Shortcuts**: Mentions (`@`), Saved posts (bookmark) and Settings (gear) each open the right-hand panel — recent mentions, flagged posts, and app actions (zoom reset, reconnect, account info, logout).

### 2. Left Channel Sidebar (`#1E325C`)
- **Team Header**: Dropdown team selector header (*None ⌄*) with a `+` action that creates a team and switches to it.
- **Sidebar Navigation**: 264 pt sidebar laid out to the web client's metrics — 32 pt rows, 19 pt leading padding, a filter menu (All channels / Favorites), a live `Find channel` filter, and a `Threads` row.
- **Channel Actions**: `Add Channels` opens a Browse Channels list with join support; `Invite Members` sends email invitations.
- **Collapsible Categories**: Custom categories (e.g. `MOJ_CAT`), `CHANNELS`, and `DIRECT MESSAGES`. Favoriting a channel (★) moves it into a `FAVORITES` branch at the top and removes it from its original category; unfavoriting returns it.
- **Unread & Mentions**: Channel rows show unread counts and blue mention pills backed by server memberships, and the timeline marks the first unread post with a "New Messages" divider. Opening a channel marks it read.
- **Active Channel Highlight**: Blue 4 pt accent pill (`#5D89EA`) at the row's leading edge over an 8% white highlight, matching the web client.

### 3. Right Chat Panel (`#FFFFFF`)
- **Channel Header**: Favorite star toggle (`☆`, persisted), channel title dropdown (View Info, Pinned Posts, favorite toggle, Copy Link, Leave Channel), member count badge (opens the Members panel), and pinned posts indicator (opens Pinned Posts).
- **Right-hand Panel**: Threads, Members and Pinned Posts lists with hover states, empty states and click-to-open, toggled from the sidebar Threads row or the header buttons.
- **Welcome Hero**: Channel introduction illustration, welcome title, description, and workspace invitation action.
- **Message Timeline**: White date-separator pills (13 pt bold over a 1 pt rule) for *Today*, *Yesterday*, weekday, or full date, with 32 pt avatars, 14 pt semibold authors, and 12.6 pt timestamps measured from the web DOM. Scrolling to the top loads older pages (60 at a time) via `before` pagination without losing your place.
- **Rich Posts**: Image previews and downloadable file chips, grouped reaction chips, pinned-post pins, an ✎ Edited marker, and deleted-message tombstones.
- **Rich Text**: Bold/italic/strike, fenced and inline code with tinted backgrounds, highlighted `@mentions`, clickable `~channel` links, expanded `:emoji:` shortcodes, inline images and external links.
- **Localized Dates**: Timestamps, date separators and panel rows use the system locale and 24-hour setting, with relative Today/Yesterday labels.
- **Message Composer**: Single-row composer matching the web client (2 pt translucent border, 4 pt radius, 50 pt editor plus a 24 pt `Help` footer), with an `Aa` toggle that expands the full formatting toolbar (*Bold*, *Italic*, *Strikethrough*, *Heading*, *Link*, *Code*, *Quote*, *Bulleted/Numbered Lists*), an emoji picker, `NSOpenPanel` attachment upload (`POST /files` + `file_ids`), and a 48×32 *Send* button.
- **Typography**: Bundles Open Sans (SIL OFL 1.1, see `mattermost.client/OpenSans-OFL.txt`) and registers it at launch so text metrics match the web client instead of falling back to the system font.

### 4. Live REST API v4 & Real-Time WebSockets
- **Team & Channel Sync**: `GET /api/v4/users/me/teams`, `GET /api/v4/users/me/teams/{team_id}/channels`, and `GET /api/v4/users/me/teams/{team_id}/channels/categories`.
- **Posts & Messaging**: Fetches channel posts (`GET /api/v4/channels/{channel_id}/posts`) and sends new messages (`POST /api/v4/posts`).
- **Real-Time WebSocket**: Bidirectional event streaming for incoming messages (`posted`), user presence (`status_change`), and live typing indicators (`typing`). Reconnects with exponential backoff and shows an in-app connection banner until the socket is healthy.

### 5. macOS System Integration
- **Status Bar Item**: System menu bar icon with click-to-toggle window visibility.
- **Dynamic UI Zoom & Scaling**: Native macOS View menu and keyboard shortcuts (`⌘+` / `⌘=` to zoom in, `⌘-` to zoom out, `⌘0` to reset to actual size), plus trackpad pinch-to-zoom and `⌘`+scroll wheel. A stored zoom level always wins; when none is saved the app defers to the OS display scale and renders at actual size. A transient HUD shows the current percentage for two seconds after each change.
- **Window Frame**: Opens at the web client's viewport (1440×783, clamped to the screen) and remembers the last frame via `NSWindow` autosave.
- **Unread Badges & Notifications**: Incoming messages for channels you are not looking at bump a blue dot on the menu-bar icon, set the Dock badge, and post a native macOS notification; opening the channel (or returning to the app) clears them.
- **App Sandbox & Keychain**: The bearer token and account password are stored in the macOS Keychain as generic-password items scoped to this app; plaintext values written by older builds are migrated and deleted at launch.
- **Transport Security**: HTTPS with port 443 is the default; explicit `http://` endpoints are allowed only for local networks through a scoped App Transport Security exception (`NSAllowsLocalNetworking`).

---

## Requirements

- **Operating System**: macOS 14.0 or newer (the app and tests build against a 14.0 deployment target)
- **Development Tools**: Xcode 16.0+ with Command Line Tools
- **Mattermost Server**: Compatible with Mattermost Server v7.0+ (REST API v4 and WebSocket v4)

---

## Quick Start

### Build

Compile the application with Xcode command line tools:

```bash
./build.sh
```

### Run

Launch the built debug application bundle:

```bash
./run.sh
```

On first launch, enter your Mattermost server URL and your user credentials. HTTPS is the default: a bare hostname such as `mattermost.example.com` resolves over `https://` on port 443. Cleartext `http://` must be typed explicitly and is restricted to local-network servers by App Transport Security — for example `http://192.168.1.10` with port `8065`. Credentials are stored in the macOS Keychain for subsequent launches.

### Run Unit Tests

Execute the automated test suite covering URL construction, JSON decoding, and WebSocket event payloads:

```bash
./test.sh
```

### Package Release DMG

Build a Release configuration and create a standalone `.dmg` installer:

```bash
./build_release.sh
```

---

## Project Structure

```text
mattermost.client/
├── build.sh                                    # Compiles the debug .app bundle
├── run.sh                                      # Launches the compiled application
├── test.sh                                     # Runs the unit test suite via xcrun xctest
├── build_release.sh                            # Builds Release build and packages DMG installer
├── LICENSE                                     # MIT License
├── README.md                                   # Project documentation
├── mattermost.client.xcodeproj                 # Xcode project file
├── mattermost.client/                          # Application source code
│   ├── main.swift                              # Application entry point
│   ├── AppDelegate.swift                       # Lifecycle, status bar item, and window controller
│   ├── KeychainHelper.swift                    # Sandboxed persistent credential and token storage
│   ├── mattermost_client.entitlements          # App Sandbox entitlements and network permissions
│   ├── webservice/
│   │   └── webservice.swift                    # REST API client and WebSocket service
│   ├── widgets/
│   │   ├── OutlinePanel.swift                  # Custom outline panel widget
│   │   └── RoundedEdgePanel.swift              # Custom rounded container panel widget
│   ├── windows/
│   │   ├── LoginWindow.swift                   # Authentication window
│   │   └── MainWindow.swift                    # Main workspace window (Header, Sidebar, Chat)
│   └── Assets.xcassets/                        # App icons, status bar icons, and vector SVGs
└── mattermost.clientTests/                     # Unit test bundle
    └── WebServiceTests.swift                   # WebService & WebSocket parsing tests
```

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
