# talos-browser.app

The download page and release notes for Talos. A Next.js app with shadcn/ui,
exported to static HTML and published by GitHub Pages
(`.github/workflows/pages.yml`).

```bash
pnpm install
pnpm dev        # http://localhost:3101 (3000 is the union app)
pnpm build      # writes out/ — what Pages serves
```

What the release workflow writes here, and what the app reads:

- `public/downloads/appcast.xml` — the Sparkle feed the app checks.
- `public/downloads/latest.json` — the current version and DMG link; the
  download button is built from it.
- `content/releases.json` — one entry per release, newest first; the
  What's New page is built from it.

Everything else is hand-written. Pages come out as folders with an
`index.html` (`trailingSlash`), so `/whats-new/` and `/downloads/…` keep the
URLs the app already uses.
