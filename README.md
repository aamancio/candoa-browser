# Talos Browser

> Talos Browser was called Candoa Browser until September 2026. The name
> changed; the app, its bundle identity, and its update feed did not. Old
> links to the candoa-browser repository redirect here.

A lightweight browser workspace for macOS.

Talos Browser is an open-source Mac browser workspace for people who live in tabs, move
between projects, and want browsing to stay native, quiet, and
battery-conscious.

[Releases](https://github.com/aamancio/talos-browser/releases) · [Discussions](https://github.com/aamancio/talos-browser/discussions)

## Why Talos Browser

Most modern browsers ship a whole cross-platform stack. Talos Browser takes a simpler
Mac-first path: SwiftUI, AppKit where native behavior needs it, and Apple's
WebKit through `WKWebView`.

That means Talos Browser can focus on the workflow:

- A sidebar-first browser surface
- Spaces for separating work, personal browsing, projects, and research
- Pinned tabs and vertical tabs
- Fast keyboard navigation
- Split view for two pages at once
- Local session restore and history
- Optional iCloud sync for workspace state
- Automatic updates through Sparkle

Talos Browser is built independently with native Apple technologies and WebKit.

## Status

Talos Browser is in beta and updates most days. See
[Releases](https://github.com/aamancio/talos-browser/releases) for the current
version.

Working today: Spaces with iCloud sync, vertical and pinned tabs, split view,
a quick search that targets a site directly, ad and tracker blocking with no
extension needed, extensions installed straight from the Chrome Web Store
(AI assistants such as Claude Code and Codex install that way), a floating
mini player that takes a video with you when you switch tabs, and automatic
updates through Sparkle.

Not there yet: an equivalent of Arc's peek window. DRM playback is unverified,
so assume some streaming services may not work until proven otherwise.

Expect rough edges. Battery efficiency and native macOS behavior are treated as
product features rather than implementation details.

## Download

Get the latest build from [talos-browser.app](https://talos-browser.app) or
straight from the [Releases](https://github.com/aamancio/talos-browser/releases)
page. Builds are
signed and notarized and update themselves through Sparkle.

## Build From Source

Requirements:

- macOS 14 or newer
- Xcode

Open `Talos.xcodeproj`, select the `Talos` scheme, then build and run.

From Terminal:

```sh
cd TalosBrowser
xcodebuild -project "Talos.xcodeproj" -scheme "Talos" -configuration Debug -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Talos.app"
```

## Project Principles

- Keep the app native to macOS.
- Use WebKit, not Chromium, Electron, CEF, or Firefox.
- Preserve familiar browser shortcuts for comparable features.
- Prefer native SwiftUI and AppKit controls over custom lookalikes.
- Keep background tabs cheap so idle browsing stays efficient.
- Avoid copying another browser's visual identity.

## Keyboard Shortcuts

Talos reserves familiar macOS browser shortcuts for comparable features.

- `Cmd+T`: New tab / command surface
- `Cmd+W`: Close current tab
- `Cmd+L`: Focus address/search bar
- `Cmd+Shift+T`: Reopen last closed tab
- `Cmd+D`: Pin or unpin current tab
- `Cmd+Shift+C`: Copy current tab URL
- `Cmd+Shift+Option+C`: Copy current tab URL as Markdown
- `Cmd+S`: Show or hide sidebar
- `Cmd+Shift+S`: Save page as…
- `Cmd+Shift+K`: Clear unpinned tabs
- `Cmd+1`, `Cmd+2`, `Cmd+3`: Go directly to a tab
- `Control+1`, `Control+2`, `Control+3`: Focus a Space
- `Control+Tab`: Toggle between recent tabs
- `Cmd+Option+Up` / `Cmd+Option+Down`: Switch tabs
- `Cmd+Option+Left` / `Cmd+Option+Right`: Switch Spaces
- `Cmd+Left` or `Cmd+[`: Back
- `Cmd+Right` or `Cmd+]`: Forward
- `Cmd+R`: Reload
- `Cmd+F`: Find in page

## For Contributors

The app is organized around a small native browser core:

- `BrowserStore` owns browser state and user actions.
- `WebViewCoordinator` owns reusable `WKWebView` instances.
- `PersistenceService` stores Spaces, tabs, selection, and local history.
- `NavigationService` handles URL and search input.
- `FaviconService` fetches and caches page icons.

Important paths:

```text
Talos/
  App/
  Models/
  Views/
  Services/
  Web/
  Resources/
Scripts/
Benchmarks/
```

Architecture decisions:

- [Sign in with Apple and Developer ID distribution](docs/sign-in-with-apple-distribution.md)

Contributions are welcome, especially around native Mac behavior,
keyboard-first browsing, WebKit lifecycle, and battery efficiency.

Please keep changes aligned with the project principles above. In particular,
do not introduce another browser engine, do not add idle polling, and do not
copy another browser's branding, icons, assets, or exact UI.

## Releases

Release builds are packaged as a drag-to-Applications DMG, attached to a GitHub
Release, and announced through the Sparkle appcast at
`https://talos-browser.app/downloads/appcast.xml`, which lives in `site/public/`
next to the download page and What's New (a Next.js site, exported static). See `docs/RELEASING.md`. The
release build carries Apple's managed browser passkey entitlement, so it must
be signed with the release identity; debug builds run without it and use the
built-in stand-in authenticator.

Talos has no accounts and no server of its own; the only network services it
uses are Apple's (iCloud sync, passkeys) and the update feed above.

Local DMG packaging:

```sh
xcodebuild -project "Talos.xcodeproj" -scheme "Talos" -configuration Release -derivedDataPath build/DerivedData build
Scripts/package_dmg.sh \
  build/DerivedData/Build/Products/Release/Talos.app \
  artifacts/Talos.dmg
```

## License

Talos is open source under the Mozilla Public License 2.0. See `LICENSE`.

## Trademark

The Talos name, icon, and app identity are not covered by the source-code
license. Forks and modified builds should use a different name and identity.

See `TRADEMARKS.md` for the project trademark policy.
