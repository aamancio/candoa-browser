# AGENTS.md

## Product Direction

Luma is intended to be an Arc-style browser workspace clone for macOS, while still feeling native to macOS and original in its implementation details.

Use Arc as the primary product/interaction benchmark:
- Sidebar-first browser workflow
- Spaces, pinned tabs, vertical tabs, and keyboard-first navigation
- Minimal top chrome
- Hidden sidebar behavior with left-edge reveal
- Contained browser surface with subtle outer spacing/border
- Keyboard shortcuts should match Arc behavior wherever Luma implements the same feature.
- Do not invent replacement shortcuts for Arc-like features. If the Arc shortcut is unknown, inspect Arc, check current Arc documentation, or leave the feature unassigned until it is verified.
- The command/new-tab surface should follow Arc's shortcut model, including using Command-T for the new tab/command bar flow rather than Command-K.

## Arc Keyboard Shortcut Parity

Primary source: Arc Help Center, "Keyboard Shortcuts" at https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts. Verify against the current official Arc documentation before changing or adding shortcuts.

Luma should use Arc's macOS shortcuts for any feature it implements. If a feature is not implemented yet, reserve the Arc shortcut and do not assign it to a different behavior.

Everyday use:
- New tab / command bar flow: Command-T
- New window: Command-N
- New incognito window: Command-Shift-N
- Close current tab or window: Command-W
- Open Little Arc equivalent: Command-Option-N
- Re-open last closed tab: Command-Shift-T
- Pin or unpin current tab: Command-D
- Copy current tab URL: Command-Shift-C
- Copy current tab URL as Markdown: Command-Shift-Option-C
- Change current tab URL / focus address bar: Command-L
- Show or hide sidebar: Command-S
- Clear unpinned tabs: Command-Shift-K

Quick navigation:
- Go directly to tab N: Command-1, Command-2, Command-3, and so on
- Focus on Space N: Control-1, Control-2, Control-3, and so on
- Toggle between recent tabs: Control-Tab
- Switch between tabs: Command-Option-Up Arrow and Command-Option-Down Arrow
- Switch between Spaces: Command-Option-Left Arrow and Command-Option-Right Arrow
- Go forward in tab history: Command-Right Arrow and Command-Right Bracket
- Go back in tab history: Command-Left Arrow and Command-Left Bracket
- Add Split View: Control-Shift-Plus
- Close Split View: Control-Shift-Minus
- Switch Split View focus: Control-Shift-1, Control-Shift-2, and so on

Other browser actions:
- View History: Command-Y
- Zoom in webpage: Command-Plus
- Zoom out webpage: Command-Minus
- Reset webpage zoom: Command-0
- Reload webpage: Command-R
- Find in webpage: Command-F

Use Zen Browser as an additional open-source product and implementation reference:
- Reference: https://github.com/zen-browser/desktop
- Treat the Zen Browser desktop codebase as available reference material for layout, interaction behavior, theme behavior, browser chrome structure, workspace/space flows, and detailed UI mechanics when Luma is implementing a comparable feature.
- When a Luma behavior is unclear, inspect Zen's repository and source files to understand the product intent and mechanics before inventing a new interaction.
- Translate useful Zen concepts into Luma's architecture using Swift, SwiftUI, AppKit where needed, and WKWebView. Preserve a native macOS feel and SwiftUI implementation style.
- Do not copy Zen code, branding, icons, assets, exact visual identity, Firefox-specific architecture, XUL/CSS implementation details, or browser engine assumptions.
- Zen is a reference for behavior and structure, not a dependency or source to paste from.

## Technical Guardrails

- Keep Luma native to macOS.
- Use Swift, SwiftUI, AppKit only where needed for native window behavior, and WKWebView.
- Do not use Chromium, CEF, Electron, Firefox, or any external browser engine.
- Preserve the lightweight WebKit-native architecture.
- Keep WKWebView lifecycle separate from SwiftUI view state.
- Keep the project modular and MVVM-friendly.

## Design Guardrails

- The app should feel like a native macOS Arc-inspired browser, not a web app shell.
- Do not directly copy Arc or Zen branding, icons, UI assets, or exact visual identity.
- Prefer native macOS materials, subtle spacing, clean borders, and restrained animation.
- Match the spirit of Arc/Zen layout behavior while keeping Luma visually original.
