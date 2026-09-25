import type { Metadata } from "next"
import { Bricolage_Grotesque, Instrument_Serif } from "next/font/google"

import "./globals.css"
import { SiteFooter } from "@/components/site-footer"
import { SiteHeader } from "@/components/site-header"
import { ThemeProvider } from "@/components/theme-provider"
import { cn } from "@/lib/utils"

const sans = Bricolage_Grotesque({
  subsets: ["latin"],
  variable: "--font-sans",
})

const serif = Instrument_Serif({
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
  variable: "--font-serif",
})

export const metadata: Metadata = {
  metadataBase: new URL("https://talos-browser.app"),
  title: {
    default: "Talos Browser",
    template: "%s · Talos",
  },
  description:
    "A native macOS browser workspace built on WebKit. Spaces, vertical tabs, keyboard-first navigation, and nothing running in the background.",
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={cn("font-sans antialiased", sans.variable, serif.variable)}
    >
      <body className="flex min-h-svh flex-col">
        <ThemeProvider>
          <SiteHeader />
          <main className="flex-1">{children}</main>
          <SiteFooter />
        </ThemeProvider>
      </body>
    </html>
  )
}
