# Mattermost macOS Client (`mattermost.client`)

A native macOS desktop client for [Mattermost](https://mattermost.com/) built with Swift and AppKit. It pairs a pixel-accurate reproduction of the modern Mattermost web workspace interface with native macOS performance, status bar integration, and live Mattermost REST API v4 / WebSocket synchronization.

---

## Highlights & Features

### 1. Top Global Header Bar (`#192A4D`)
- **Product Switcher**: Custom grid app switcher (`E82F`) and Mattermost logo with `TEAM EDITION` badge, opening an interactive menu (*Channels*, *System Console*, *Integrations*, *App Marketplace*, *Download Apps*, *About Mattermost*).
- **Search Popover**: Centered search bar with quick popover offering *Messages* / *Files* tabs, bordered search input, and filter hint pills (`from:`, `in:`, `on:`).
- **Help Menu**: Quick help (`?`) popup menu linking to Mattermost guides, resources, and shortcuts.
- **User Status & Profile**: User avatar with online dot and dropdown menu (*@username*, *Set custom status*, *Online*, *Away*, *Do not disturb* with *Clear after:* submenu, *Offline*, *Profile*, *Log out*).
- **Action Shortcuts**: Direct access buttons for Mentions (`@`), Saved posts (bookmark), and Settings.

### 2. Left Channel Sidebar (`#1E325C`)
- **Team Header**: Dropdown team selector header (*None ⌄*) with quick-create (`+`) action.
- **Sidebar Navigation**: Channel filter button, rounded `Find channel` search pill, and `Threads` row.
- **Collapsible Categories**: Custom categories (e.g. `MOJ_CAT`), `CHANNELS`, and `DIRECT MESSAGES`.
- **Active Channel Highlight**: Left accent bar, translucent background highlight, and bold channel title.

### 3. Right Chat Panel (`#FFFFFF`)
- **Channel Header**: Favorite star toggle (`☆`), channel title dropdown, member count badge, and pinned posts indicator.
- **Welcome Hero**: Channel introduction illustration, welcome title, description, and workspace invitation action.
- **Message Timeline**: Centered date separators with avatar-attributed message rows, sender status badges, timestamps, and message bodies.
- **Message Composer**: Full text formatting toolbar (*Bold*, *Italic*, *Strikethrough*, *Heading*, *Link*, *Code*, *Quote*, *Bulleted/Numbered Lists*, *Emoji picker*, *Attachment*, and *Send* button).

### 4. Live REST API v4 & Real-Time WebSockets
- **Team & Channel Sync**: `GET /api/v4/users/me/teams`, `GET /api/v4/users/me/teams/{team_id}/channels`, and `GET /api/v4/users/me/teams/{team_id}/channels/categories`.
- **Posts & Messaging**: Fetches channel posts (`GET /api/v4/channels/{channel_id}/posts`) and sends new messages (`POST /api/v4/posts`).
- **Real-Time WebSocket**: Bidirectional event streaming for incoming messages (`posted`), user presence (`status_change`), and live typing indicators (`typing`).

### 5. macOS System Integration
- **Status Bar Item**: System menu bar icon with click-to-toggle window visibility.
- **Dynamic UI Zoom & Scaling**: Native macOS View menu and keyboard shortcuts (`⌘+` / `⌘=` to zoom in, `⌘-` to zoom out, `⌘0` to reset to actual size) with persistent zoom levels stored in `UserDefaults`.
- **App Sandbox**: Secure preference storage isolated to the app container without system Keychain permission dialogs on launch.

---

## Requirements

- **Operating System**: macOS 14.0 or newer
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

On first launch, enter your Mattermost server URL (e.g., `https://mattermost.example.com` or `http://127.0.0.1`), port (`8065` or `443`), and your user credentials. Credentials are automatically saved to your sandboxed container preferences for subsequent launches.

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
