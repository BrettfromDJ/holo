"use client";

import { ArrowUpRight } from "lucide-react";

/**
 * One button: "View on" and TCGplayer's logo, opening the card's TCGplayer page. No figures:
 * our source can't say which condition TCGplayer's market price is for. Same as the app's
 * `WorthPanel`.
 */
export function WhatsItWorth({ tcgplayerUrl, tcgplayerId }: { nm?: number | null; tcgplayerUrl?: string | null; tcgplayerId?: number | null }) {
  const url = tcgplayerUrl ?? (tcgplayerId ? `https://www.tcgplayer.com/product/${tcgplayerId}` : null);
  if (!url) return null;
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
