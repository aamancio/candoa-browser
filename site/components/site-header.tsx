import Link from "next/link"

import { REPO_URL } from "@/lib/releases"

export function SiteHeader() {
  return (
    <header className="border-b">
      <div className="mx-auto flex h-14 w-full max-w-3xl items-center justify-between px-4 sm:px-6">
        <Link href="/" className="flex items-center gap-2 font-medium">
          <TalosMark className="size-6" />
          Talos
        </Link>
        <nav className="flex items-center gap-5 text-sm text-muted-foreground">
          <Link href="/whats-new/" className="hover:text-foreground">
            What&apos;s new
          </Link>
          <a href={REPO_URL} className="hover:text-foreground">
            GitHub
          </a>
        </nav>
      </div>
    </header>
  )
}

export function TalosMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" aria-hidden="true" className={className}>
      <rect width="64" height="64" rx="14" className="fill-primary" />
      <rect
        x="14"
        y="16"
        width="10"
        height="32"
        rx="3"
        className="fill-primary-foreground"
      />
      <rect
        x="28"
        y="16"
        width="22"
        height="9"
        rx="3"
        className="fill-primary-foreground/80"
      />
      <rect
        x="28"
        y="28"
        width="22"
        height="9"
        rx="3"
        className="fill-primary-foreground/60"
      />
      <rect
        x="28"
        y="40"
        width="22"
        height="8"
        rx="3"
        className="fill-primary-foreground/40"
      />
    </svg>
  )
}
