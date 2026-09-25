import Link from "next/link"

import { TalosMark } from "@/components/site-header"
import { latestRelease, RELEASES_URL, REPO_URL } from "@/lib/releases"

export function SiteFooter() {
  const latest = latestRelease()

  const columns = [
    {
      title: "Get Talos",
      links: [
        {
          label: "Download",
          href: latest ? latest.downloadURL : `${RELEASES_URL}/latest`,
        },
        { label: "All releases", href: RELEASES_URL },
        { label: "What's new", href: "/whats-new/" },
      ],
    },
    {
      title: "Project",
      links: [
        { label: "Source on GitHub", href: REPO_URL },
        { label: "Report an issue", href: `${REPO_URL}/issues` },
        { label: "License (MPL 2.0)", href: `${REPO_URL}/blob/main/LICENSE` },
      ],
    },
  ]

  return (
    <footer className="mt-24 border-t">
      <div className="mx-auto grid w-full max-w-6xl gap-10 px-5 py-14 sm:grid-cols-[1.5fr_1fr_1fr] sm:px-8">
        <div className="flex max-w-xs flex-col gap-3">
          <Link href="/" className="flex items-center gap-2.5 font-semibold">
            <TalosMark className="size-7" />
            Talos
          </Link>
          <p className="text-sm text-muted-foreground">
            A browser workspace for the Mac. Native, quiet, and yours.
          </p>
        </div>
        {columns.map((col) => (
          <div key={col.title} className="flex flex-col gap-3 text-sm">
            <h3 className="font-semibold">{col.title}</h3>
            <ul className="flex flex-col gap-2 text-muted-foreground">
              {col.links.map((l) =>
                l.href.startsWith("/") ? (
                  <li key={l.label}>
                    <Link href={l.href} className="hover:text-foreground">
                      {l.label}
                    </Link>
                  </li>
                ) : (
                  <li key={l.label}>
                    <a href={l.href} className="hover:text-foreground">
                      {l.label}
                    </a>
                  </li>
                )
              )}
            </ul>
          </div>
        ))}
      </div>
      <div className="mx-auto w-full max-w-6xl px-5 pb-10 text-sm text-muted-foreground sm:px-8">
        Talos was called Candoa Browser until September 2026.
      </div>
    </footer>
  )
}
