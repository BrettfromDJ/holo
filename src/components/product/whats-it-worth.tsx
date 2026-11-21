"use client";

import { ArrowUpRight } from "lucide-react";

/**
 * One quiet glass button, "View on TCGplayer" (text only), under the card's actions. No figures:
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
      className="mt-3 flex h-11 items-center justify-center gap-1.5 rounded-[14px] border border-white/10 bg-white/[0.06] text-[15px] font-semibold text-white backdrop-blur-xl transition-colors hover:bg-white/[0.1]"
    >
      View on TCGplayer
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
