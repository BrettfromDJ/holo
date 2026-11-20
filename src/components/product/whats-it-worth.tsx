"use client";

import { ArrowUpRight } from "lucide-react";

/**
 * A link to the card on TCGplayer, with its logo. No prices: our source can't say which
 * condition TCGplayer's figures are for, so TCGplayer shows them itself. Same as the app's
 * `WorthPanel`.
 */
export function WhatsItWorth({ tcgplayerUrl, tcgplayerId }: { nm?: number | null; tcgplayerUrl?: string | null; tcgplayerId?: number | null }) {
  const url = tcgplayerUrl ?? (tcgplayerId ? `https://www.tcgplayer.com/product/${tcgplayerId}` : null);
  if (!url) return null;
  return (
    <section className="mt-6 rounded-[var(--radius-card)] border border-[#2F5BFF]/30 bg-surface bg-[radial-gradient(ellipse_at_top,rgba(47,91,255,0.25),transparent_70%)] p-5 sm:p-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-[15px] font-semibold">Prices by condition</h2>
          <p className="mt-0.5 text-[12px] text-muted">Near Mint to Damaged, straight from TCGplayer</p>
        </div>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brands/tcgplayer.svg" alt="TCGplayer" className="h-[26px] w-auto" />
      </div>
      <a
        href={url}
        target="_blank"
        rel="noreferrer"
        className="mt-5 flex h-11 items-center justify-center gap-2 rounded-full bg-[#2F5BFF] text-[15px] font-semibold text-white hover:opacity-90"
      >
        View on TCGplayer <ArrowUpRight className="size-4" />
      </a>
    </section>
  );
}
