import { GeistMono } from "geist/font/mono";
import { GeistSans } from "geist/font/sans";
import type { Metadata, Viewport } from "next";
import { Anton } from "next/font/google";
import { AppShell } from "@/components/shell/app-shell";
import "./globals.css";

// Condensed all-caps display face for high-energy headlines.
const display = Anton({ weight: "400", subsets: ["latin"], variable: "--font-anton", display: "swap" });

export const metadata: Metadata = {
  title: { default: "Holo — Pokémon Collection Tracker", template: "%s · Holo" },
  description: "Track the market value and investment performance of your Pokémon cards and sealed products.",
  applicationName: "Holo",
  // Added to the iPhone home screen, Holo opens full-screen under a translucent status bar.
  appleWebApp: { capable: true, title: "Holo", statusBarStyle: "black-translucent" },
  formatDetection: { telephone: false },
  // Older iOS versions only go full-screen with this one.
  other: { "apple-mobile-web-app-capable": "yes" },
};

export const viewport: Viewport = {
  themeColor: "#0b0b0c",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

// Apply the saved theme before first paint to avoid a flash.
const themeScript = `try{var t=localStorage.getItem("holo:theme");var l=t==="light"||(t==="system"&&matchMedia("(prefers-color-scheme: light)").matches);document.documentElement.classList.toggle("light",l);document.documentElement.classList.toggle("dark",!l)}catch(e){}`;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`dark ${GeistSans.variable} ${GeistMono.variable} ${display.variable}`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body>
        <AppShell>{children}</AppShell>
      </body>
    </html>
  );
}
