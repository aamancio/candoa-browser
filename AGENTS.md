# AGENTS.md

## Product Direction

Luma Browser is intended to be an Arc-style browser workspace clone for macOS, while still feeling native to macOS and original in its implementation details.

Use Arc as the primary product/interaction benchmark:
- Sidebar-first browser workflow
- Spaces, pinned tabs, vertical tabs, and keyboard-first navigation
- Minimal top chrome
- Hidden sidebar behavior with left-edge reveal
- Contained browser surface with subtle outer spacing/border
- Keyboard shortcuts should match Arc behavior wherever Luma implements the same feature.
- Do not invent replacement shortcuts for Arc-like features. If the Arc shortcut is unknown, inspect Arc, check current Arc documentation, or leave the feature unassigned until it is verified.
- The command/new-tab surface should follow Arc's shortcut model, including using Command-T for the new tab/command bar flow rather than Command-K.

Use Zen Browser as an additional open-source layout reference:
- Reference: https://github.com/zen-browser/desktop
- Use Zen only for layout and interaction inspiration.
- Do not copy Zen code, branding, assets, or Firefox-specific architecture.

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
