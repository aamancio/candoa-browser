import Image from "next/image"

// The real window, captured by Scripts/site-screenshots.sh from a clean
// workspace: one image per appearance, each shown only in its own theme.
export function AppScreenshot() {
  const alt =
    "Talos with the sidebar open: favourites, the Work space, three tabs, and a GitHub page"
  return (
    <div className="mx-auto w-full max-w-5xl overflow-hidden rounded-2xl border shadow-[0_30px_80px_-30px_rgb(0_0_0/0.45)] sm:rounded-3xl">
      <Image
        src="/screenshots/talos-light.webp"
        alt={alt}
        width={2400}
        height={1506}
        priority
        className="block h-auto w-full dark:hidden"
      />
      <Image
        src="/screenshots/talos-dark.webp"
        alt={alt}
        width={2400}
        height={1506}
        priority
        className="hidden h-auto w-full dark:block"
      />
    </div>
  )
}
