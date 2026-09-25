import Link from "next/link"
import { ArrowRight } from "lucide-react"

import { buttonVariants } from "@/components/ui/button"
import { latestRelease, RELEASES_URL, REPO_URL } from "@/lib/releases"
import { cn } from "@/lib/utils"

export function SiteHeader() {
  const latest = latestRelease()
  const downloadHref = latest ? latest.downloadURL : `${RELEASES_URL}/latest`

  return (
    <header className="sticky top-0 z-10 bg-background/80 backdrop-blur">
      <div className="mx-auto flex h-16 w-full max-w-6xl items-center justify-between px-5 sm:px-8">
        <Link href="/" className="flex items-center gap-2.5 font-semibold">
          <TalosMark className="size-7" />
          Talos
        </Link>
        <nav className="hidden items-center gap-7 text-sm font-medium sm:flex">
          <Link
            href="/whats-new/"
            className="text-foreground/80 hover:text-foreground"
          >
            What&apos;s new
          </Link>
          <a
            href={REPO_URL}
            className="text-foreground/80 hover:text-foreground"
          >
            GitHub
          </a>
        </nav>
        <a
          href={downloadHref}
          className={cn(buttonVariants({ size: "lg" }), "rounded-full px-4")}
        >
          Download
          <ArrowRight data-icon="inline-end" />
        </a>
      </div>
    </header>
  )
}

export function TalosMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" aria-hidden="true" className={className}>
      <rect width="64" height="64" rx="16" className="fill-foreground" />
      <rect
        x="14"
        y="16"
        width="10"
        height="32"
        rx="3"
        className="fill-background"
      />
      <rect x="28" y="16" width="22" height="9" rx="3" className="fill-coral" />
      <rect
        x="28"
        y="28"
        width="22"
        height="9"
        rx="3"
        className="fill-background/70"
      />
      <rect
        x="28"
        y="40"
        width="22"
        height="8"
        rx="3"
        className="fill-background/40"
      />
    </svg>
  )
}
