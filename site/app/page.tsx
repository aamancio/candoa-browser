import Link from "next/link"
import { Download } from "lucide-react"

import { buttonVariants } from "@/components/ui/button"
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { latestRelease, RELEASES_URL } from "@/lib/releases"
import { cn } from "@/lib/utils"

const features = [
  {
    title: "Spaces",
    text: "Work, personal, a project, a rabbit hole. Each one keeps its own tabs, synced through iCloud.",
  },
  {
    title: "Vertical and pinned tabs",
    text: "A sidebar you can read, with the tabs you keep at the top.",
  },
  {
    title: "Keyboard first",
    text: "One command bar for addresses, search, and every action, with the shortcuts you already know.",
  },
  { title: "Split view", text: "Two pages side by side when you need them." },
  {
    title: "Blocking built in",
    text: "Ads and trackers stop at WebKit's content rules. No extension, no script watching you.",
  },
  {
    title: "Chrome extensions",
    text: "Install straight from the Chrome Web Store. AI assistants such as Claude Code and Codex come this way.",
  },
  {
    title: "Passkeys",
    text: "Sign in with the passkeys in your Apple Passwords, confirmed with Touch ID.",
  },
  { title: "Mini player", text: "A video follows you to the next tab." },
]

const notes = [
  "Talos is in beta and updates itself through Sparkle. Expect rough edges.",
  "Nothing phones home. There are no accounts and no server behind the app; iCloud sync is Apple's.",
  "DRM playback is unverified, so some streaming services may not work yet.",
]

export default function Page() {
  const latest = latestRelease()

  return (
    <div className="flex flex-col gap-14">
      <section className="flex flex-col gap-6">
        <div className="flex flex-col gap-3">
          <h1 className="text-4xl font-semibold tracking-tight sm:text-5xl">
            Talos
          </h1>
          <p className="max-w-xl text-lg text-muted-foreground">
            A browser workspace for the Mac. Native SwiftUI on Apple&apos;s
            WebKit, so it stays quiet, light on the battery, and out of your
            way.
          </p>
        </div>
        <div className="flex flex-col gap-2">
          <div>
            <a
              href={latest ? latest.downloadURL : `${RELEASES_URL}/latest`}
              className={cn(
                buttonVariants({ size: "lg" }),
                "h-10 px-4 text-base"
              )}
            >
              <Download data-icon="inline-start" />
              {latest
                ? `Download Talos ${latest.version}`
                : "Download for macOS"}
            </a>
          </div>
          <p className="text-sm text-muted-foreground">
            macOS 14 or newer.{" "}
            <a
              href={RELEASES_URL}
              className="underline underline-offset-4 hover:text-foreground"
            >
              All releases
            </a>
            {latest ? (
              <>
                {" "}
                ·{" "}
                <Link
                  href="/whats-new/"
                  className="underline underline-offset-4 hover:text-foreground"
                >
                  What&apos;s new in {latest.version}
                </Link>
              </>
            ) : null}
          </p>
        </div>
      </section>

      <section className="flex flex-col gap-4">
        <h2 className="text-xl font-semibold tracking-tight">What it does</h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {features.map((f) => (
            <Card key={f.title} size="sm">
              <CardHeader>
                <CardTitle>{f.title}</CardTitle>
                <CardDescription>{f.text}</CardDescription>
              </CardHeader>
            </Card>
          ))}
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-xl font-semibold tracking-tight">Honest notes</h2>
        <ul className="list-disc space-y-1.5 pl-5 text-muted-foreground">
          {notes.map((n) => (
            <li key={n}>{n}</li>
          ))}
        </ul>
      </section>
    </div>
  )
}
