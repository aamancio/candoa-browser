import Image from "next/image"

// The hero: a silent looping tour of the real window, one clip per
// appearance, recorded by Scripts/site-screenshots.sh from a clean
// workspace. The still from the same run is the poster, and it is all
// people see when they have asked their system to reduce motion.
//
// The <video> tags are written as HTML because React drops the `muted`
// attribute from server output, and a video without it will not autoplay.
const ALT =
  "Talos with the sidebar open: favourites, the Work space, three tabs, and a GitHub page"

function video(appearance: "light" | "dark") {
  return `<video class="block h-auto w-full motion-reduce:hidden" autoplay muted loop playsinline preload="metadata" poster="/screenshots/talos-${appearance}.webp" aria-label="${ALT}">
  <source src="/screenshots/talos-${appearance}.mp4" type="video/mp4" />
</video>`
}

export function AppShowcase() {
  return (
    <div className="mx-auto w-full max-w-5xl overflow-hidden rounded-2xl border bg-muted shadow-[0_30px_80px_-30px_rgb(0_0_0/0.45)] sm:rounded-3xl">
      <div className="dark:hidden">
        <div dangerouslySetInnerHTML={{ __html: video("light") }} />
        <Image
          src="/screenshots/talos-light.webp"
          alt={ALT}
          width={2400}
          height={1506}
          className="hidden h-auto w-full motion-reduce:block"
        />
      </div>
      <div className="hidden dark:block">
        <div dangerouslySetInnerHTML={{ __html: video("dark") }} />
        <Image
          src="/screenshots/talos-dark.webp"
          alt={ALT}
          width={2400}
          height={1506}
          className="hidden h-auto w-full motion-reduce:block"
        />
      </div>
    </div>
  )
}
