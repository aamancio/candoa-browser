import releases from "@/content/releases.json"
import latest from "@/public/downloads/latest.json"

// Both files are written by the release workflow (.github/workflows/release.yml)
// and read here at build time, so the site never fetches anything at runtime.

export type Release = {
  version: string
  date: string
  new: string[]
  fixed: string[]
}

export type Latest = {
  version: string
  build: string
  bundleIdentifier: string
  fileName: string
  downloadURL: string
  appcastURL: string
  releaseNotesURL: string
}

export const RELEASES_URL = "https://github.com/aamancio/talos-browser/releases"
export const REPO_URL = "https://github.com/aamancio/talos-browser"

export function listReleases(): Release[] {
  return releases as Release[]
}

export function latestRelease(): Latest | null {
  const l = latest as Partial<Latest>
  return l && l.version && l.downloadURL ? (l as Latest) : null
}

export function formatDate(iso: string) {
  return new Date(`${iso}T12:00:00Z`).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  })
}
