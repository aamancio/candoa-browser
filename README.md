# Luma Browser

Luma Browser is an open-source, Arc-inspired browser workspace for Mac. It uses a sidebar-first interface with spaces, vertical tabs, pinned tabs, keyboard-first navigation, and a lightweight WebKit-native browsing experience.

Luma is inspired by sidebar-first browser workflows, but it does not copy Arc branding, icons, UI assets, or exact visual design.

## Features

- Native macOS SwiftUI app
- WKWebView-only browsing engine
- Sidebar-first workspace
- Spaces
- Pinned tabs and regular tabs
- Multiple reusable WKWebView-backed tabs
- Two-tab split view
- Active tab switching
- Drag and drop tab reordering
- Address/search bar
- Back, forward, reload, and stop controls
- Live page title updates
- Loading progress indicators
- Favicon fetching and caching
- Session restore with lightweight JSON persistence
- `Cmd+L` focuses the address/search bar
- `Cmd+K` opens a command palette shell
- Command palette actions and tab search across spaces

## Keyboard Shortcuts

- `Cmd+T`: New tab
- `Cmd+W`: Close current tab
- `Cmd+L`: Focus address/search bar
- `Cmd+K`: Open command palette
- `Cmd+Shift+]`: Next tab
- `Cmd+Shift+[`: Previous tab
- `Cmd+Option+Right`: Next space
- `Cmd+Option+Left`: Previous space

## Tech Stack

- Swift
- SwiftUI
- WebKit / WKWebView
- Combine
- JSON persistence in Application Support
- macOS target

## Project Status

Early prototype. The first milestone focuses on proving the native app shell, WebKit tab model, sidebar workspace, and persistence architecture.

## Setup

1. Open `Luma.xcodeproj` in Xcode.
2. Select the `Luma Browser` scheme.
3. Build and run on macOS.

From Terminal:

```sh
cd ~/Projects/candoa/luma
xcodebuild -project "Luma.xcodeproj" -scheme "Luma Browser" -configuration Debug -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Luma Browser.app"
```

## Folder Structure

```text
Luma/
  App/
  Models/
  Views/
  Services/
  Web/
  Resources/
```

## Architecture

- `BrowserStore` owns browser state and exposes actions for views.
- `PersistenceService` saves and restores spaces, tabs, and active selection.
- `NavigationService` normalizes URL input and search queries.
- `WebViewCoordinator` owns and reuses `WKWebView` instances per tab.
- `FaviconService` fetches page-discovered icons with a lightweight in-memory cache.
- SwiftUI views stay thin and call store/service methods.

## Roadmap

- Real favicons
- Tab drag and reorder
- Space rename/delete controls
- Split views
- Themes
- Downloads
- History
- Bookmark import/export
- AI page summaries
- Smarter tab organization
- Optional sync layer

## Contributing

Contributions are welcome. Keep the app native, lightweight, battery-friendly, and WebKit-only. Avoid external browser engines such as Chromium, CEF, Electron, or Firefox.

## License

MIT License. See `LICENSE`.
# luma
