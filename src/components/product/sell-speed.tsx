"use client";

import { Info } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { cachedEbay } from "@/lib/ebay-client";
import { sampleEbaySales } from "@/lib/ebay-sample";
import type { EbaySales } from "@/lib/ebay-types";
import { SELL_SPEED_NOTE, sellSpeed, type SellSpeed, type SellSpeedTier } from "@/lib/liquidity";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { useEbayData } from "./ebay-sales";

/** Whether a product has eBay sales to score: catalog cards, and demo ones (sample sales). */
export function hasEbayData(productId: string) {
  return productId.startsWith("tcgapi:") || productId.startsWith("sample:");
}

const SEGMENTS: Record<SellSpeedTier, number> = { "Sells fast": 3, "Sells steady": 2, "Slow to sell": 1 };

/** Three segments: 3 filled for Sells fast, 2 for Sells steady, 1 (pink) for Slow to sell. */
export function SellSpeedBar({ tier, small, className }: { tier: SellSpeedTier; small?: boolean; className?: string }) {
  const filled = SEGMENTS[tier];
  return (
    <span aria-hidden className={cn("inline-flex shrink-0 items-center gap-0.5", className)}>
      {[0, 1, 2].map((i) => (
        <span
          key={i}
          className={cn("rounded-full", small ? "h-1 w-[7px]" : "h-1.5 w-2.5", i < filled ? (tier === "Slow to sell" ? "bg-[var(--plan-pink)]" : "bg-[var(--lime)]") : "bg-foreground/15")}
        />
      ))}
    </span>
  );
}

/**
 * The "Sells fast" meter: the segments, the tier, then "82% · 14 sold this month" with only the
 * percentage colored. `compact` is just the segments and the tier (the Deal tab). Same as the
 * app's `SellSpeedMeter`.
 */
export function SellSpeedMeter({ speed, compact, className }: { speed: SellSpeed; compact?: boolean; className?: string }) {
  const [explain, setExplain] = useState(false);
  if (compact) {
    return (
      <span className={cn("inline-flex items-center gap-1.5 text-[11px] text-muted", className)}>
        <SellSpeedBar tier={speed.tier} small />
        {speed.tier}
      </span>
    );
  }
  const tone = speed.score >= 70 ? "text-[var(--lime)]" : speed.score >= 40 ? "text-foreground" : "text-[var(--plan-pink)]";
  return (
    <div className={className}>
      <button
        type="button"
        onClick={() => setExplain((v) => !v)}
        aria-expanded={explain}
        aria-label={`${speed.tier}, ${speed.score}%, ${speed.sold} sold this month. What this means`}
        className="group flex w-full min-w-0 items-center gap-2 text-left"
      >
        <SellSpeedBar tier={speed.tier} />
        <span className="shrink-0 text-[14px] font-semibold">{speed.tier}</span>
        <span className="tabular min-w-0 truncate text-[13px] text-muted">
          <span className={tone}>{speed.score}%</span> · {speed.sold} sold this month
        </span>
        <Info className="ml-auto size-3.5 shrink-0 text-subtle transition-colors group-hover:text-foreground" />
      </button>
      {explain && <p className="mt-1.5 text-[12px] text-muted">{SELL_SPEED_NOTE}</p>}
    </div>
  );
}

/** "Not enough sales yet", in the meter's place. */
export function SellSpeedEmpty({ className }: { className?: string }) {
  return (
    <p className={cn("flex items-center gap-2 text-[13px] text-muted", className)}>
      <SellSpeedBar tier="Slow to sell" className="opacity-35" />
      Not enough sales yet
    </p>
  );
}

/** The meter for one eBay result and grade label (null = ungraded). */
export function SellSpeedFromSales({ ebay, grade, className }: { ebay: EbaySales; grade: string | null; className?: string }) {
  const { today } = useStore();
  const speed = useMemo(() => sellSpeed(ebay, grade, today), [ebay, grade, today]);
  return speed ? <SellSpeedMeter speed={speed} className={className} /> : <SellSpeedEmpty className={className} />;
}

/**
 * The meter for one copy (a grade label for slabs, else ungraded), from the same eBay data the
 * card page uses (one request per card, shared and cached on the device). Hidden for products
 * without eBay data, and while it loads.
 */
export function SellSpeedFor({ productId, printing, grade, className }: { productId: string; printing: string | null; grade: string | null; className?: string }) {
  const supported = hasEbayData(productId);
  const { load } = useEbayData(productId, printing, { active: supported });
  if (!supported || load.state !== "ready" || !load.data) return null;
  return <SellSpeedFromSales ebay={load.data} grade={grade} className={className} />;
}

/**
 * Just the tier, for a deal line: only when the card's eBay sales are already on this device
 * (never fetched per line). Demo products' sample sales are made on the spot.
 */
export function SellSpeedTag({ productId, printing, grade, name, market, className }: { productId: string; printing: string | null; grade: string | null; name: string; market: number | null; className?: string }) {
  const { today } = useStore();
  // Read after mount: the device cache isn't there on the server.
  const [ebay, setEbay] = useState<EbaySales | null>(null);
  useEffect(() => {
    if (productId.startsWith("sample:")) setEbay(sampleEbaySales(productId, name, printing, market, today));
    else if (productId.startsWith("tcgapi:")) setEbay(cachedEbay(productId, printing)?.value ?? null);
    else setEbay(null);
  }, [productId, printing, name, market, today]);
  const speed = useMemo(() => (ebay ? sellSpeed(ebay, grade, today) : null), [ebay, grade, today]);
  return speed ? <SellSpeedMeter speed={speed} compact className={className} /> : null;
}
