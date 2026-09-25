import Link from "next/link"

import { REPO_URL } from "@/lib/releases"

export function SiteFooter() {
  return (
    <footer className="border-t">
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-1 px-4 py-8 text-sm text-muted-foreground sm:px-6">
        <p className="flex flex-wrap gap-x-3">
          <Link href="/whats-new/" className="hover:text-foreground">
            What&apos;s new
          </Link>
          <a href={REPO_URL} className="hover:text-foreground">
            Source on GitHub
          </a>
          <span>Mozilla Public License 2.0</span>
        </p>
        <p>Talos was called Candoa Browser until September 2026.</p>
      </div>
    </footer>
  )
}
