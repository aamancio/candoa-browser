# Command fixture

An unpacked extension whose one command, `open-marker-tab`, is bound to
⌘E. When the command fires it opens a tab whose title names the command
and says which of Chrome's panel APIs WebKit exposes (`sidePanel`,
`notifications`, `sidebarAction` — all `undefined` on macOS 26).

A UI-testing launch loads it with `TALOS_UI_TESTING_EXTENSION=<path>`; the
app is sandboxed, so copy the folder somewhere its container can read
(`~/Library/Containers/app.candoa.browser/Data/tmp/`) first. Then post the
key through the window-command channel:

    notify app.talos.uitesting.window-command key:Command-E

A marker tab appearing proves the key reached the extension. Recorded
2026-09-25 while chasing a tester's "⌘E does nothing" with Claude in
Chrome: the key arrives; the extension then wants a side panel WebKit
cannot show.
