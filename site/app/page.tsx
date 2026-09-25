import Link from "next/link"
import { ArrowRight } from "lucide-react"

import { AppScreenshot } from "@/components/app-screenshot"
import { buttonVariants } from "@/components/ui/button"
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
  {
    title: "Split view",
    text: "Two pages side by side when you need them.",
  },
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
  {
    title: "Mini player",
    text: "A video follows you to the next tab.",
  },
]

const values = [
  {
    title: "Native and light",
    text: "SwiftUI on Apple's WebKit. It launches fast, sips the battery, and looks like it belongs on a Mac.",
  },
  {
    title: "Nothing phones home",
    text: "No accounts, no server behind the app, no telemetry. iCloud sync is Apple's and stays in your keychain.",
  },
  {
    title: "Open and honest",
    text: "Mozilla Public License, source on GitHub. Talos is in beta and updates itself through Sparkle; expect rough edges, and DRM video is unverified.",
  },
]

export default function Page() {
  const latest = latestRelease()
  const downloadHref = latest ? latest.downloadURL : `${RELEASES_URL}/latest`

  return (
    <div className="flex flex-col gap-28 sm:gap-36">
      <section className="mx-auto flex w-full max-w-6xl flex-col items-center gap-10 px-5 pt-16 text-center sm:px-8 sm:pt-28">
        <h1 className="font-serif text-[3.25rem] leading-[0.95] tracking-tight text-balance sm:text-8xl">
          a browser that
          <br />
          stays <em className="text-brand">out of your way</em>
        </h1>
        <p className="max-w-xl text-lg text-balance text-muted-foreground">
          Talos is a browser workspace for the Mac. Native SwiftUI on
          Apple&apos;s WebKit, so it stays quiet, light on the battery, and
          yours.
        </p>
        <div className="flex flex-col items-center gap-4">
          <div className="flex flex-wrap justify-center gap-3">
            <a
              href={downloadHref}
              className={cn(
                buttonVariants({ size: "lg" }),
                "h-11 rounded-full px-5 text-base"
              )}
            >
              Download for macOS
              <ArrowRight data-icon="inline-end" />
            </a>
            <Link
              href="/whats-new/"
              className={cn(
                buttonVariants({ variant: "secondary", size: "lg" }),
                "h-11 rounded-full px-5 text-base"
              )}
            >
              What&apos;s new
            </Link>
          </div>
          <p className="text-sm text-muted-foreground">
            {latest ? `Version ${latest.version} · ` : ""}macOS 14 or newer ·{" "}
            <a
              href={RELEASES_URL}
              className="underline underline-offset-4 hover:text-foreground"
            >
              all releases
            </a>
          </p>
        </div>
        <div className="w-full pt-6">
          <AppScreenshot />
        </div>
      </section>

      <section className="mx-auto grid w-full max-w-6xl gap-12 px-5 sm:grid-cols-[1fr_1.4fr] sm:px-8">
        <div className="flex flex-col gap-4 sm:sticky sm:top-28 sm:self-start">
          <h2 className="font-serif text-5xl leading-none tracking-tight sm:text-6xl">
            Built for <em className="text-brand">focus</em>
          </h2>
          <p className="max-w-sm text-muted-foreground">
            A browser should help you get through the day, not keep you in it.
            Everything in Talos is there to make the next thing quicker to
            reach.
          </p>
        </div>
        <div className="grid gap-x-10 gap-y-10 sm:grid-cols-2">
          {features.map((f) => (
            <div key={f.title} className="flex flex-col gap-2">
              <h3 className="text-lg font-semibold">{f.title}</h3>
              <p className="text-muted-foreground">{f.text}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto flex w-full max-w-6xl flex-col gap-12 px-5 sm:px-8">
        <div className="flex max-w-2xl flex-col gap-4">
          <h2 className="font-serif text-5xl leading-none tracking-tight sm:text-6xl">
            What we <em className="text-brand">won&apos;t</em> do
          </h2>
          <p className="text-muted-foreground">
            The promises are simpler than the features.
          </p>
        </div>
        <div className="grid gap-8 sm:grid-cols-3">
          {values.map((v) => (
            <div
              key={v.title}
              className="flex flex-col gap-2 rounded-3xl bg-muted/60 p-7"
            >
              <h3 className="text-lg font-semibold">{v.title}</h3>
              <p className="text-muted-foreground">{v.text}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto flex w-full max-w-6xl flex-col items-center gap-6 px-5 text-center sm:px-8">
        <h2 className="font-serif text-5xl leading-none tracking-tight sm:text-6xl">
          Try it <em className="text-brand">today</em>
        </h2>
        <a
          href={downloadHref}
          className={cn(
            buttonVariants({ size: "lg" }),
            "h-11 rounded-full px-5 text-base"
          )}
        >
          Download for macOS
          <ArrowRight data-icon="inline-end" />
        </a>
      </section>
    </div>
  )
}
