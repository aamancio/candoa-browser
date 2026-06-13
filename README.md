# Candoa

Candoa is an open-source, Arc-inspired browser workspace for macOS.

The goal is to build the browser I want to use every day: a native-feeling Mac app with Arc-style navigation, a sidebar-first workspace, spaces, pinned tabs, vertical tabs, and keyboard-driven tab management. Candoa is not trying to copy Arc's branding, assets, or exact visual identity. It is an independent implementation of a similar workflow.

Candoa uses Apple's WebKit through `WKWebView`, the same browser engine family behind Safari. That choice is intentional. I want Candoa to stay lightweight, battery-conscious, easier to maintain, and native to macOS instead of becoming a Chromium, Electron, CEF, or Firefox-based app.

This project is currently built around my personal browsing workflow. For development-heavy work I still often use Chrome, but Candoa is where I am exploring a more focused, native, keyboard-first browser experience.

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
- Optional iCloud sync preparation for Spaces, open tabs, and pinned tabs through CloudKit
- Optional separate iCloud history sync toggle, off by default
- Space-scoped WebKit website data stores for isolated cookies, cache, localStorage, and IndexedDB
- `Cmd+L` focuses the address/search bar
- `Cmd+T` opens the command/new-tab surface
- Command palette actions and tab search across spaces

## Keyboard Shortcuts

Candoa aims to match Arc's macOS keyboard shortcuts for Arc-like features it implements. When an Arc shortcut is unknown or a feature is not implemented yet, the shortcut should remain unassigned instead of being reused for a different behavior.

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

1. Open `Candoa.xcodeproj` in Xcode.
2. Select the `Candoa` scheme.
3. Build and run on macOS.

From Terminal:

```sh
cd ~/Projects/Candoa/Candoa
xcodebuild -project "Candoa.xcodeproj" -scheme "Candoa" -configuration Debug -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Candoa.app"
```

## iCloud Sync

Candoa is local-only by default. The Browser > iCloud Sync menu can opt the app into syncing workspace state through the user's private iCloud database. History has a separate opt-in toggle and stays local-only unless explicitly enabled.

The sync layer intentionally does not sync cookies, cache, localStorage, IndexedDB, website sessions, downloads, or private browsing state. Those remain in the local `WKWebsiteDataStore`.

To test real iCloud sync, enable the iCloud capability in Xcode with an Apple Developer team and add a CloudKit container named:

```text
iCloud.org.candoa.Candoa
```

The project currently keeps that entitlement out of source control because the default manual/ad-hoc signing setup cannot build with iCloud entitlements and no provisioning profile. Once the capability is enabled for your team, turn on Browser > iCloud Sync > Enable iCloud Sync for Spaces and Tabs, relaunch Candoa, and test with another signed-in Mac using the same iCloud account.

## Folder Structure

```text
Candoa/
  App/
  Models/
  Views/
  Services/
  Web/
  Resources/
```

## Architecture

- `BrowserStore` owns browser state and exposes actions for views.
- `PersistenceService` saves Spaces, tabs, active selection, and Space data-store identifiers in `~/Library/Application Support/Candoa/CandoaSession.sqlite`.
- `PersistenceService` saves history visits in `~/Library/Application Support/Candoa/CandoaHistory.sqlite`.
- Legacy `~/Library/Application Support/Luma/` and `~/Library/Application Support/Luma Browser/` data is moved under Candoa on first launch, including old split stores and the older combined `Luma.sqlite` store.
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

- Keep Candoa native to macOS.
- Use Swift, SwiftUI, AppKit where needed, and `WKWebView`.
- Do not introduce Chromium, CEF, Electron, Firefox, or another browser engine.
- Keep `WKWebView` lifecycle separate from SwiftUI view state.
- Prefer Arc shortcut parity for Arc-like features.
- Avoid copying Arc or Zen branding, icons, assets, or exact UI.
- Keep the codebase approachable for a small open-source project.

By submitting a contribution, you agree it is provided under the project's MPL-2.0 license.

## License

Candoa is open source under the Mozilla Public License 2.0 (MPL-2.0) — the same license used by Firefox, Zen, and Brave. See `LICENSE`.

In short: you are free to use, build, modify, and redistribute Candoa, but if you distribute modified versions of Candoa's source files, those files must remain available under MPL-2.0. This is not legal advice; the `LICENSE` text is what governs.

Code contributed before the license change was published under the MIT License; from this point forward the project is MPL-2.0.

## Trademark

"Candoa" and the Candoa app identity are not covered by the source-code license. You may not use the Candoa name, icon, or branding for forks, modified builds, or derived products without permission. Forks must ship under a different name and identity.
