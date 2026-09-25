import type { Metadata } from "next"

import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { formatDate, listReleases } from "@/lib/releases"

export const metadata: Metadata = {
  title: "What's new",
  description: "Every Talos release, newest first.",
}

export default function Page() {
  const releases = listReleases()

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-col gap-2">
        <h1 className="text-3xl font-semibold tracking-tight">
          What&apos;s new
        </h1>
        <p className="text-muted-foreground">
          Every Talos release, newest first.
        </p>
      </div>

      {releases.length === 0 ? (
        <p className="text-muted-foreground">No releases yet.</p>
      ) : (
        <div className="flex flex-col">
          {releases.map((r, i) => (
            <article
              key={r.version}
              id={`v${r.version}`}
              className="flex flex-col gap-4"
            >
              {i > 0 ? <Separator className="my-8" /> : null}
              <div className="flex flex-wrap items-center gap-3">
                <h2 className="text-xl font-semibold tracking-tight">
                  Talos {r.version}
                </h2>
                {i === 0 ? <Badge>Latest</Badge> : null}
                <time
                  dateTime={r.date}
                  className="text-sm text-muted-foreground"
                >
                  {formatDate(r.date)}
                </time>
              </div>
              {r.new.length === 0 && r.fixed.length === 0 ? (
                <p className="text-muted-foreground">Maintenance release.</p>
              ) : null}
              <Changes title="New" items={r.new} />
              <Changes title="Fixed" items={r.fixed} />
            </article>
          ))}
        </div>
      )}
    </div>
  )
}

function Changes({ title, items }: { title: string; items: string[] }) {
  if (items.length === 0) return null
  return (
    <div className="flex flex-col gap-2">
      <h3 className="text-xs font-medium tracking-wider text-muted-foreground uppercase">
        {title}
      </h3>
      <ul className="list-disc space-y-1.5 pl-5">
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </div>
  )
}
