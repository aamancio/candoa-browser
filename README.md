# Luma Browser

Luma Browser is an open-source, Arc-inspired browser workspace for macOS.

The goal is to build the browser I want to use every day: a native-feeling Mac app with Arc-style navigation, a sidebar-first workspace, spaces, pinned tabs, vertical tabs, and keyboard-driven tab management. Luma is not trying to copy Arc's branding, assets, or exact visual identity. It is an independent implementation of a similar workflow.

Luma uses Apple's WebKit through `WKWebView`, the same browser engine family behind Safari. That choice is intentional. I want Luma to stay lightweight, battery-conscious, easier to maintain, and native to macOS instead of becoming a Chromium, Electron, CEF, or Firefox-based app.

This project is currently built around my personal browsing workflow. For development-heavy work I still often use Chrome, but Luma is where I am exploring a more focused, native, keyboard-first browser experience.

## Product Goals

- Arc-style sidebar navigation without copying Arc's visual identity
- Native macOS feel using SwiftUI, AppKit where needed, and WebKit
- Keyboard-first browser workflows
- Spaces, pinned tabs, vertical tabs, and fast switching
- Minimal top chrome with the browser surface as the focus
- Lightweight architecture that a small open-source project can maintain
- Battery-conscious browsing through WebKit instead of a bundled browser engine

## Features

- Native macOS SwiftUI app
- `WKWebView`-only browsing engine
- Sidebar-first workspace
- Spaces with name, icon, theme, and local site-data scope
- Space switcher with rename, delete, icon, theme color, and tab move actions
- Pinned tabs and regular tabs
- Multiple reusable `WKWebView`-backed tabs
- Two-tab split view
- Active tab switching
- Drag and drop tab reordering
- Address/search bar
- Back, forward, reload, and stop controls
- Live page title updates
- Loading progress indicators
- Favicon fetching and caching
- Session restore with local Core Data / SQLite persistence
- Local-only history visit recording
- Space-scoped WebKit website data stores for isolated cookies, cache, localStorage, and IndexedDB
- `Cmd+L` focuses the address/search bar
- `Cmd+T` opens the command/new-tab surface
- Command palette actions and tab search across spaces

## Keyboard Shortcuts

Luma aims to match Arc's macOS keyboard shortcuts for Arc-like features it implements. When an Arc shortcut is unknown or a feature is not implemented yet, the shortcut should remain unassigned instead of being reused for a different behavior.

- `Cmd+T`: New tab / command surface
- `Cmd+W`: Close current tab
- `Cmd+L`: Focus address/search bar
- `Cmd+Shift+T`: Reopen last closed tab
- `Cmd+D`: Pin or unpin current tab
- `Cmd+Shift+C`: Copy current tab URL
- `Cmd+Shift+Option+C`: Copy current tab URL as Markdown
- `Cmd+S`: Show or hide sidebar
- `Cmd+Shift+K`: Clear unpinned tabs
- `Cmd+1`, `Cmd+2`, `Cmd+3`, and so on: Go directly to tab
- `Control+1`, `Control+2`, `Control+3`, and so on: Focus space
- `Control+Tab`: Toggle between recent tabs
- `Cmd+Option+Up`: Previous tab
- `Cmd+Option+Down`: Next tab
- `Cmd+Option+Left`: Previous space
- `Cmd+Option+Right`: Next space
- `Cmd+Left` or `Cmd+[`: Back
- `Cmd+Right` or `Cmd+]`: Forward
- `Cmd+R`: Reload
- `Cmd+F`: Find in page

## Tech Stack

- Swift
- SwiftUI
- AppKit where native window behavior needs it
- WebKit / `WKWebView`
- Combine
- Core Data / SQLite persistence in Application Support
- macOS target

## Project Status

Early prototype. The first milestone focuses on proving the native app shell, WebKit tab model, sidebar workspace, keyboard flow, and persistence architecture.

Expect rough edges. The intent is to keep iterating in public while preserving the core direction: native macOS, Arc-inspired workflow, and WebKit-only browsing.

## Setup

1. Open `Luma.xcodeproj` in Xcode.
2. Select the `Luma Browser` scheme.
3. Build and run on macOS.

From Terminal:

```sh
cd ~/Projects/Candoa/Luma
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
- `PersistenceService` saves spaces, tabs, active selection, Space data-store identifiers, and history visits in `~/Library/Application Support/Luma Browser/Luma.sqlite`.
- `NavigationService` normalizes URL input and search queries.
- `WebViewCoordinator` owns and reuses `WKWebView` instances per tab, creating them with the active Space's WebKit website data store.
- `FaviconService` fetches page-discovered icons with a lightweight in-memory cache.
- SwiftUI views stay thin and call store/service methods.

## Roadmap

- Arc-parity keyboard shortcut audit
- Hidden sidebar with left-edge reveal
- Deeper space management
- Profile manager for assigning multiple Spaces to one data profile
- Better split views
- Downloads
- History UI and search
- Bookmark import/export
- Themes
- Smarter tab organization
- Optional sync layer

## Contributing

Contributions are welcome, especially if you care about native Mac software, keyboard-first browsing, and lightweight browser architecture.

Please keep changes aligned with the project direction:

- Keep Luma native to macOS.
- Use Swift, SwiftUI, AppKit where needed, and `WKWebView`.
- Do not introduce Chromium, CEF, Electron, Firefox, or another browser engine.
- Keep `WKWebView` lifecycle separate from SwiftUI view state.
- Prefer Arc shortcut parity for Arc-like features.
- Avoid copying Arc or Zen branding, icons, assets, or exact UI.
- Keep the codebase approachable for a small open-source project.

## License

MIT License. See `LICENSE`.
