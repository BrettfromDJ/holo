"use client";

import { useEffect, useMemo, useState } from "react";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { Badge } from "@/components/ui/badge";
import { loadConditions } from "@/lib/ebay-client";
import type { ConditionPrice } from "@/lib/ebay-types";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money, signedMoney } from "@/lib/format";
import { rawWorth, RAW_CONDITIONS, type RawCondition, type Worth } from "@/lib/worth";
import { cn } from "@/lib/utils";
import { conditionHue, useEbayData } from "./ebay-sales";

const CONDITION_BY_LABEL: Record<string, RawCondition> = Object.fromEntries(RAW_CONDITIONS.map((c) => [c.label, c.id]));

/**
 * One question, one number: what is this card worth raw, in the condition you pick? Real
 * prices first (TCGplayer per condition, then eBay sales); estimates are always marked.
 * Grades are in the Graded prices panel above. Opens on the condition you own.
 */
export function WhatsItWorth({ productId, printing, name, nm, owned }: { productId: string; printing: string | null; name: string; nm: number | null; owned: HoldingView[] }) {
  const rawHeld = owned.find((h) => !h.identity.grade);
  const [condition, setCondition] = useState<RawCondition>(CONDITION_BY_LABEL[rawHeld?.identity.condition ?? ""] ?? "NM");
  const { load, sampleMode } = useEbayData(productId, printing, { name, market: nm, active: true });
  const ebay = load.state === "ready" ? load.data : null;
  // TCGplayer prices per condition, for real cards (Pro plan).
  const [conditions, setConditions] = useState<ConditionPrice[] | null>(null);
  useEffect(() => {
    if (sampleMode || !productId.startsWith("tcgapi:")) return;
    let cancelled = false;
    loadConditions(productId, printing)
      .then((rows) => !cancelled && setConditions(rows))
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [productId, printing, sampleMode]);

  const worth: Worth | null = useMemo(() => (nm === null ? null : rawWorth(nm, condition, ebay, conditions, printing)), [nm, condition, ebay, conditions, printing]);

  if (nm === null || !worth) return null;
  const vsNm = worth.price - nm;
  const label = RAW_CONDITIONS.find((c) => c.id === condition)!.label;
  const yours = rawHeld && CONDITION_BY_LABEL[rawHeld.identity.condition] === condition;
  const estimate = worth.source === "estimate";

  return (
    <section className="mt-6 rounded-[var(--radius-card)] border border-border bg-surface p-5 sm:p-6">
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-display text-[22px] uppercase leading-none tracking-[0.01em] sm:text-[24px]">What&apos;s it worth raw?</h2>
        {sampleMode && <Badge variant="sample">Sample data</Badge>}
      </div>

      {/* The answer */}
      <div className="mt-5 flex items-end justify-between gap-3">
        <p className={cn("hype-num tabular text-[clamp(40px,12vw,56px)] leading-none", estimate && "text-foreground/85")}>
          <AnimatedNumber value={worth.price} from={worth.price} duration={500} format={money} />
        </p>
        <span className="mb-1 shrink-0 text-right">
          <span className="block text-[14px] font-semibold">{label}</span>
          {yours && <span className="block text-[11px] text-muted">Yours</span>}
        </span>
      </div>
      <SourceLine worth={worth} />
      {condition !== "NM" && (
        <p className="tabular mt-1 text-[12px] text-muted">
          <span className={vsNm >= 0 ? "text-up" : "text-down"}>{signedMoney(vsNm)}</span> vs Near Mint ({money(nm)})
        </p>
      )}

      {/* The picker */}
      <div className="mt-5 grid grid-cols-5 gap-1.5" role="radiogroup" aria-label="Condition">
        {RAW_CONDITIONS.map((c) => {
          const on = condition === c.id;
          const hue = conditionHue(c.label);
          return (
            <button
              key={c.id}
              type="button"
              role="radio"
              aria-checked={on}
              aria-label={c.label}
              onClick={() => setCondition(c.id)}
              className={cn("h-11 rounded-xl text-[14px] font-semibold transition-colors", on ? "ring-2" : "bg-surface-2 text-muted hover:text-foreground")}
              style={on && hue ? { background: `color-mix(in srgb, ${hue} 18%, transparent)`, color: `color-mix(in srgb, ${hue} 85%, var(--foreground))`, ["--tw-ring-color" as string]: hue } : undefined}
            >
              {c.id}
            </button>
          );
        })}
      </div>
    </section>
  );
}

/** Where the number came from, with estimates set apart so they're never mistaken for sales. */
function SourceLine({ worth }: { worth: Worth }) {
  const tag = { market: "Market price", sales: "eBay sales", guide: "Price guide", estimate: "Estimate" }[worth.source];
  return (
    <p className="mt-2 flex flex-wrap items-center gap-2 text-[12px] text-muted">
      <span
        className={cn(
          "rounded-full px-2 py-0.5 text-[11px] font-semibold",
          worth.source === "estimate" ? "border border-dashed border-border-strong text-foreground/80" : worth.source === "sales" ? "bg-[color-mix(in_srgb,var(--lime)_16%,transparent)] text-up" : "bg-surface-2 text-foreground/80",
        )}
      >
        {tag}
      </span>
      {worth.detail}
    </p>
  );
}
