"use client";

import { ArrowUpRight } from "lucide-react";

/**
 * One button: "View on" and TCGplayer's logo, opening the card's TCGplayer page. No figures:
 * our source can't say which condition TCGplayer's market price is for. Same as the app's
 * `WorthPanel`.
 */
export function WhatsItWorth({ tcgplayerUrl, tcgplayerId, printing, sealed }: { nm?: number | null; tcgplayerUrl?: string | null; tcgplayerId?: number | null; printing?: string | null; sealed?: boolean }) {
  const base = tcgplayerUrl ?? (tcgplayerId ? `https://www.tcgplayer.com/product/${tcgplayerId}` : null);
  if (!base) return null;
  const url = withPrinting(base, printing, sealed);
  return (
    <a
      href={url}
      target="_blank"
      rel="noreferrer"
      className="mt-6 flex h-12 items-center justify-center gap-2 rounded-full bg-[#2F5BFF] text-[15px] font-semibold text-white hover:opacity-90"
    >
      View on
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/brands/tcgplayer.svg" alt="TCGplayer" className="h-[18px] w-auto" />
      <ArrowUpRight className="size-4" />
    </a>
  );
}

/**
 * TCGplayer's own filters for the printing shown and Near Mint, on a product page link
 * (otherwise it opens on whatever it likes, often a cheaper printing in Lightly Played).
 */
export function withPrinting(url: string, printing?: string | null, sealed?: boolean): string {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return url;
  }
  if (!u.pathname.includes("/product/")) return url;
  u.searchParams.set("Language", "English");
  if (printing) u.searchParams.set("Printing", printing);
  else u.searchParams.delete("Printing");
  if (sealed) u.searchParams.delete("Condition");
  else u.searchParams.set("Condition", "Near Mint");
  return u.toString();
}
