// A drawn window, not a screenshot: a sidebar of Spaces and vertical tabs
// next to a quiet page. It stands in until the app has a real hero image.
export function BrowserMock() {
  const tabs = [
    { w: "w-3/4", active: true },
    { w: "w-1/2" },
    { w: "w-2/3" },
    { w: "w-2/5" },
    { w: "w-3/5" },
  ]

  return (
    <div
      aria-hidden="true"
      className="mx-auto w-full max-w-5xl overflow-hidden rounded-3xl border bg-card shadow-[0_30px_80px_-30px_rgb(0_0_0/0.35)]"
    >
      <div className="grid h-[22rem] grid-cols-[13rem_1fr] sm:h-[30rem]">
        <aside className="flex flex-col gap-5 border-r bg-muted/60 p-5">
          <div className="flex gap-2">
            <span className="size-3 rounded-full bg-foreground/20" />
            <span className="size-3 rounded-full bg-foreground/20" />
            <span className="size-3 rounded-full bg-foreground/20" />
          </div>
          <div className="h-8 rounded-lg border bg-background/70" />
          <div className="flex flex-col gap-2">
            {tabs.map((t, i) => (
              <div
                key={i}
                className={
                  "flex h-8 items-center gap-2 rounded-lg px-2 " +
                  (t.active ? "bg-background shadow-sm" : "")
                }
              >
                <span
                  className={
                    "size-4 rounded-md " +
                    (t.active ? "bg-coral" : "bg-foreground/15")
                  }
                />
                <span className={"h-2 rounded-full bg-foreground/15 " + t.w} />
              </div>
            ))}
          </div>
          <div className="mt-auto flex gap-2">
            <span className="size-2.5 rounded-full bg-coral" />
            <span className="size-2.5 rounded-full bg-foreground/20" />
            <span className="size-2.5 rounded-full bg-foreground/20" />
          </div>
        </aside>
        <section className="flex flex-col gap-6 p-8 sm:p-12">
          <div className="h-3 w-1/3 rounded-full bg-foreground/15" />
          <div className="flex flex-col gap-3">
            <div className="h-2.5 w-full rounded-full bg-foreground/10" />
            <div className="h-2.5 w-11/12 rounded-full bg-foreground/10" />
            <div className="h-2.5 w-4/5 rounded-full bg-foreground/10" />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="h-28 rounded-2xl bg-foreground/[0.06]" />
            <div className="h-28 rounded-2xl bg-foreground/[0.06]" />
          </div>
          <div className="flex flex-col gap-3">
            <div className="h-2.5 w-full rounded-full bg-foreground/10" />
            <div className="h-2.5 w-2/3 rounded-full bg-foreground/10" />
          </div>
        </section>
      </div>
    </div>
  )
}
