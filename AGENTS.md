# AGENTS.md

## Hard Rules (Non-Negotiable — read before writing any code)

These three rules override everything else in this file and any default instinct. A change that violates one is wrong even if it looks good, and must not ship.

### 1. Native feel ≠ animation

"Make it feel native/smooth" is never a request to add motion. Native feel comes from correct geometry, instant response, and quiet settles — not from animating things.

- Default answer to "should this animate?" is **no**. Ship state changes as instant or near-instant first; add motion only when the *absence* of it reads as broken (e.g. a list snapping shut, an element teleporting between two real on-screen positions).
- Reference points are Apple's own apps: Safari's sidebar (rows settle when a tab closes), Finder (selection moves instantly), macOS PiP (morphs anchored to real geometry). If Safari wouldn't animate it, Candoa doesn't.
- Allowed motion vocabulary: 0.10–0.20s easeOut for chrome state changes; springs only for spatial morphs between two real positions, damped enough to show no visible bounce. Context jumps (space switch, page swap) are instant cuts.
- Never add scale pops, bounces, staggered reveals, attention-seeking transitions, or motion that exists to be noticed.

### 2. Native SwiftUI/AppKit components first — no custom re-implementations

Use the system control and style it; do not rebuild it.

- Inputs, buttons, menus, pickers, toggles, scroll views, progress indicators, context menus, popovers, alerts, focus rings, text selection: use the SwiftUI/AppKit built-in (`TextField`, `Menu`, `.contextMenu`, `.popover`, `ScrollView`, `ProgressView`, …) with modifiers. SF Symbols for icons, system materials for surfaces, system cursors via `NSCursor`.
- Do not draw custom lookalikes for native controls or native icons. Window traffic lights, toolbar controls, disclosure arrows, menu indicators, search/address fields, selection states, drag handles, and standard glyphs must come from AppKit/SwiftUI/SF Symbols whenever a native equivalent exists.
- Before writing any custom control, the bar is: *the native one provably cannot be configured to match the required Arc/Zen design*. If that bar is met, compose the custom view **from** native primitives and keep native behavior intact (keyboard navigation, focus, accessibility, standard shortcuts, text editing gestures).
- Hand-rolled text inputs, scrollbars, menu lookalikes, drawn traffic lights, custom icon paths for SF Symbol-equivalent glyphs, or re-implemented system behaviors are rejected by default.

### 3. Never trade memory or energy for anything

Battery/memory efficiency is the product's selling point (see "Battery Efficiency" below — those rules are part of this one). No visual or convenience win justifies a steady-state cost.

- Nothing persistent may be added for a transient effect: no retained snapshots, caches, extra web views, hidden always-rendered layers, observers, or timers that outlive the moment that needs them. Transition artifacts (e.g. a freeze-frame image) must be released the moment the transition ends.
- Animations run on the GPU compositor: transforms and opacity on chrome layers only. Never animate web content layout (a `WKWebView`'s frame/size), never force per-frame relayout, never animate continuously (no idle pulsing, shimmering, or breathing effects).
- If a proposed change adds any steady-state memory, idle CPU, or cross-process traffic, the default is to not build it. Raising idle resource usage is a shipping blocker, verified per the Battery Efficiency section.

## Product Direction

Candoa is intended to be an Arc-style browser workspace clone for macOS, while still feeling native to macOS and original in its implementation details.

## Related Projects

- Marketing site: `/Users/alex/Projects/Candoa/CandoaSite`
- Public app download for the marketing site lives under `/Users/alex/Projects/Candoa/CandoaSite/public/downloads/` and should be linked from the site as `/downloads/<filename>`.
- Prefer a drag-to-Applications DMG (`Candoa.dmg`) for public downloads. Zip builds are only for quick internal handoff.
- The app repo workflow `.github/workflows/update-site-download.yml` builds a Release DMG on `main` pushes and commits it to the CandoaSite repo. It expects `CANDOA_SITE_DEPLOY_KEY` as a GitHub Actions secret containing a write-enabled deploy key for the site repo; optionally set `CANDOA_SITE_REPOSITORY` and `CANDOA_SITE_BRANCH` repository variables if the defaults are wrong.

Use Arc as the primary product/interaction benchmark:
- Sidebar-first browser workflow
- Spaces, pinned tabs, vertical tabs, and keyboard-first navigation
- Minimal top chrome
- Hidden sidebar behavior with left-edge reveal
- Contained browser surface with subtle outer spacing/border
- Keyboard shortcuts should match Arc behavior wherever Candoa implements the same feature.
- Do not invent replacement shortcuts for Arc-like features. If the Arc shortcut is unknown, inspect Arc, check current Arc documentation, or leave the feature unassigned until it is verified.
- The command/new-tab surface should follow Arc's shortcut model, including using Command-T for the new tab/command bar flow rather than Command-K.

## Arc Keyboard Shortcut Parity

Primary source: Arc Help Center, "Keyboard Shortcuts" at https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts. Verify against the current official Arc documentation before changing or adding shortcuts.

Candoa should use Arc's macOS shortcuts for any feature it implements. If a feature is not implemented yet, reserve the Arc shortcut and do not assign it to a different behavior.

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
- Treat the Zen Browser desktop codebase as available reference material for layout, interaction behavior, theme behavior, browser chrome structure, workspace/space flows, and detailed UI mechanics when Candoa is implementing a comparable feature.
- When a Candoa behavior is unclear, inspect Zen's repository and source files to understand the product intent and mechanics before inventing a new interaction.
- Translate useful Zen concepts into Candoa's architecture using Swift, SwiftUI, AppKit where needed, and WKWebView. Preserve a native macOS feel and SwiftUI implementation style.
- Do not copy Zen code, branding, icons, assets, exact visual identity, Firefox-specific architecture, XUL/CSS implementation details, or browser engine assumptions.
- Zen is a reference for behavior and structure, not a dependency or source to paste from.

## Battery Efficiency (Core Feature — Always Follow)

Battery efficiency is Candoa's flagship differentiator against Arc, Brave, and Zen, and the reason Candoa uses system WebKit instead of Chromium. Every feature and change must preserve it. These rules are not optional:

- **No steady-state work on idle pages.** Never add an unconditional `setInterval`, polling timer, or recurring task to injected JavaScript or app code. Timers must be event-driven, exist only while the condition they serve is active (e.g. the media progress ticker runs only during playback), and be torn down the moment it ends.
- **Background web views stay out of the view hierarchy.** Only tabs with media stay parented (hidden) so playback survives tab switches. Everything else must be unparented so WebKit can throttle it. Do not "fix" a bug by re-parenting all background web views.
- **Tab hibernation must keep working.** Background tabs idle past `TabHibernationConfiguration.idleInterval` give up their web view and WebContent process; state is restored via `interactionState` behind a wake snapshot. New features must not silently defeat it (e.g. by touching `lastAccessedAt`, holding web view references, or adding media state to tabs without media).
- **Hibernation exemptions are a UX contract — keep the list intact:** active tab, split tab, pinned tabs, tabs with media, popups awaiting first load, and pages with unsaved form/editor input are never hibernated. Battery gains must never cost user data or break media playback.
- **Content blocking stays in the network process.** Tracker/ad blocking uses a compiled `WKContentRuleList` (`ContentBlockerService`). Do not replace it with JavaScript-based blocking. When changing the domain list, bump the rule-list identifier version so the compiled cache invalidates. Never block login-critical hosts.
- **Cross-process chatter is a battery cost.** Minimize `postMessage`/`evaluateJavaScript` traffic between the app and WebContent processes; coalesce and throttle reports rather than streaming them.
- **Prove regressions haven't happened.** For changes touching web view lifecycle, injected scripts, or timers, sanity-check with Activity Monitor's Energy Impact or the `Benchmarks/` powermetrics kit. A feature that visibly raises idle CPU does not ship.

## Technical Guardrails

- Keep Candoa native to macOS.
- Use Swift, SwiftUI, AppKit only where needed for native window behavior, and WKWebView.
- Do not use Chromium, CEF, Electron, Firefox, or any external browser engine.
- Preserve the lightweight WebKit-native architecture.
- Keep WKWebView lifecycle separate from SwiftUI view state.
- Keep the project modular and MVVM-friendly.

## Design Guardrails

- The app should feel like a native macOS Arc-inspired browser, not a web app shell.
- Do not directly copy Arc or Zen branding, icons, UI assets, or exact visual identity.
- Prefer native macOS materials, subtle spacing, clean borders, and restrained animation.
- Match the spirit of Arc/Zen layout behavior while keeping Candoa visually original.
