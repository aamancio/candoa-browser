import type { NextConfig } from "next"

// The site is a static export published by GitHub Pages (see
// .github/workflows/pages.yml). Every page becomes a folder with an
// index.html, so /whats-new/ and /downloads/… keep the URLs the app and the
// Sparkle feed already use.
const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
}

export default nextConfig
