"use client";

import { useEffect, useState } from "react";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { useInView } from "@/components/motion/reveal";
import { Card, SectionTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import type { PriceChartingGraded } from "@/lib/graded";
import { money, relativeTime } from "@/lib/format";
import type { Grade } from "@/lib/types";
import { cn } from "@/lib/utils";
import { estimatedGradedTable, GRADED_ROWS, gradedLookup, lookupGrades, WORTH_GRADERS, type WorthGrader } from "@/lib/worth";
import { useEbayData } from "./ebay-sales";

/* ------------------------- PriceCharting, per card ------------------------ */

const pcCache = new Map<string, PriceChartingGraded | null>();
const pcInflight = new Map<string, Promise<PriceChartingGraded | null>>();

function loadPriceCharting(productId: string): Promise<PriceChartingGraded | null> {
  if (pcCache.has(productId)) return Promise.resolve(pcCache.get(productId)!);
  const pending = pcInflight.get(productId);
  if (pending) return pending;
  const p = fetch(`/api/graded?ids=${encodeURIComponent(productId)}`)
    .then((r) => (r.ok ? r.json() : null))
    .then((body: { graded?: Record<string, PriceChartingGraded> } | null) => {
      const v = body?.graded?.[productId] ?? null;
      const value = v && Object.keys(v.grades).length ? v : null;
      pcCache.set(productId, value);
      return value;
    })
    .catch(() => null)
    .finally(() => pcInflight.delete(productId));
  pcInflight.set(productId, p);
  return p;
}

/**
 * PriceCharting's graded values for a card (stored nightly on the server, so free to read).
 * Only catalog cards have them; anything else is ready at once with null.
 */
export function usePriceChartingGraded(productId: string): {
  ready: boolean;
  data: PriceChartingGraded | null;
} {
  const catalog = productId.startsWith("tcgapi:");
  const [state, setState] = useState<{
    id: string;
    data: PriceChartingGraded | null;
  } | null>(() => (!catalog ? { id: productId, data: null } : pcCache.has(productId) ? { id: productId, data: pcCache.get(productId)! } : null));
  useEffect(() => {
    if (!catalog) return setState({ id: productId, data: null });
    let cancelled = false;
    void loadPriceCharting(productId).then((data) => !cancelled && setState({ id: productId, data }));
    return () => {
      cancelled = true;
    };
  }, [productId, catalog]);
  return state?.id === productId ? { ready: true, data: state.data } : { ready: false, data: null };
}

/* ------------------------------- The panel -------------------------------- */

/**
 * What the card sells for graded. PriceCharting's table first (each grade's value and how many
 * times ungraded it is, your grade highlighted), or the same table from the usual grade curve
 * when PriceCharting has nothing. Below it, look up any company and grade: eBay sales of that
 * exact slab first, then PriceCharting, then the curve. Same as the app's Graded prices panel.
 */
export function GradedPrices({ productId, printing, nm, owned, className }: { productId: string; printing: string | null; nm: number | null; owned: Grade[]; className?: string }) {
  const pc = usePriceChartingGraded(productId);
  const [ref, inView] = useInView<HTMLDivElement>("0px 0px 200px 0px");
  const { load } = useEbayData(productId, printing, {
    market: nm,
    active: inView && productId.startsWith("tcgapi:"),
  });
  const ebay = load.state === "ready" ? load.data : null;

  const slab = owned[0];
  const [company, setCompany] = useState<WorthGrader>(() => ((WORTH_GRADERS as readonly string[]).includes(slab?.company.toUpperCase() ?? "") ? (slab!.company.toUpperCase() as WorthGrader) : "PSA"));
  const [grade, setGrade] = useState<string>(() => {
    const g = slab?.grade ?? "9";
    return lookupGrades(company).includes(g) ? g : "10";
  });

  const real = pc.data;
  const table = real ?? estimatedGradedTable(productId, nm);
  const hasEbayGraded = Boolean(ebay && Object.keys(ebay.graded).length);
  if (pc.ready && !table && !hasEbayGraded) return null;

  const isOwned = (row: (typeof GRADED_ROWS)[number]) =>
    owned.some((g) => (row.company ? g.company.toUpperCase() === row.company && Number(g.grade) === 10 : Number(g.grade) === Number(row.grade) && Number(g.grade) !== 10));
  const result = gradedLookup(productId, nm, { company, grade }, ebay, real);

  return (
    <div ref={ref} className={className}>
      <Card className="p-5 sm:p-6">
        <SectionTitle
          title="Graded prices"
          subtitle={!pc.ready ? "What it sells for graded" : real ? `What it sells for graded · PriceCharting · updated ${relativeTime(real.updatedAt)}` : "Estimated from the usual grade curve"}
        />
        {!pc.ready ? (
          <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-10 w-full rounded-xl" />
            ))}
          </div>
        ) : (
          <>
            {table && (
              <>
                {table.ungraded !== null && (
                  <div className="mb-2 flex items-baseline justify-between rounded-xl bg-surface-2 px-4 py-3">
                    <span className="text-[13px] text-muted">Ungraded</span>
                    <span className="tabular text-[17px] font-semibold">{money(table.ungraded)}</span>
                  </div>
                )}
                <ul className="divide-y divide-border">
                  {GRADED_ROWS.filter((r) => table.grades[r.key] !== undefined).map((r) => {
                    const value = table.grades[r.key];
                    const multiple = table.ungraded ? value / table.ungraded : null;
                    const mine = isOwned(r);
                    return (
                      // The wash sits behind the row and reaches past it, so the row's content stays in line with the others.
                      <li key={r.key} className="relative flex items-center gap-3 py-3">
                        {mine && <span aria-hidden className="absolute -inset-x-3 inset-y-0 rounded-xl bg-[color-mix(in_srgb,var(--lime)_10%,transparent)]" />}
                        <span className="relative inline-flex min-w-[4.5rem] items-center gap-1 rounded-[6px] bg-surface-2 px-2 py-1 font-mono text-[12px] font-medium leading-none ring-1 ring-inset ring-border">
                          <span className="text-muted">{r.company ?? "Any"}</span>
                          <span className="text-foreground">{r.grade}</span>
                        </span>
                        {mine && <span className="relative text-[11px] font-semibold text-[var(--lime)]">Yours</span>}
                        <span className="relative ml-auto tabular text-[12px] text-subtle">{multiple ? `${multiple >= 10 ? multiple.toFixed(0) : multiple.toFixed(1)}× ungraded` : ""}</span>
                        <span className="relative tabular w-24 text-right text-[16px] font-semibold">{money(value)}</span>
                      </li>
                    );
                  })}
                </ul>
                <p className="mt-3 text-[12px] text-subtle">
                  {real ? "10s are per grading company; lower grades are for any company." : "No graded sales for this card yet, so these follow the usual grade curve."}
                </p>
                <div className="my-5 h-px bg-border" />
              </>
            )}

            {/* Look up any grade */}
            <p className="font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">Look up any grade</p>
            <div className="mt-3 flex flex-wrap gap-1.5" role="radiogroup" aria-label="Grading company">
              {WORTH_GRADERS.map((c) => (
                <button
                  key={c}
                  type="button"
                  role="radio"
                  aria-checked={company === c}
                  onClick={() => {
                    setCompany(c);
                    if (!lookupGrades(c).includes(grade)) setGrade("10");
                  }}
                  className={cn(
                    "h-8 rounded-full px-3.5 text-[13px] font-medium transition-colors",
                    company === c ? "bg-lime font-semibold text-[#0b0b0c] shadow-[0_0_16px_-4px_var(--lime)]" : "text-muted hover:text-foreground",
                  )}
                >
                  {c}
                </button>
              ))}
            </div>
            {/* 10 down to 5, spread across the width: nothing scrolls or clips. */}
            <div className="mt-3 flex gap-0.5 rounded-full bg-surface-2 p-[3px] ring-1 ring-inset ring-border" role="radiogroup" aria-label={`${company} grade`}>
              {lookupGrades(company).map((g) => (
                <button
                  key={g}
                  type="button"
                  role="radio"
                  aria-checked={grade === g}
                  aria-label={`${company} ${g}`}
                  onClick={() => setGrade(g)}
                  className={cn(
                    "tabular h-[30px] min-w-0 flex-1 rounded-full text-[13px] font-semibold transition-colors",
                    grade === g ? "bg-lime text-[#0b0b0c]" : "text-muted hover:text-foreground",
                  )}
                >
                  {g}
                </button>
              ))}
            </div>
            <div className="mt-3 flex items-baseline justify-between gap-3 rounded-xl bg-surface-2 px-4 py-3" aria-live="polite">
              <div className="min-w-0">
                <p className="text-[14px] font-semibold">
                  {company} {grade}
                </p>
                <p className="mt-0.5 text-[12px] text-subtle">{result.detail}</p>
              </div>
              <p className="tabular shrink-0 text-[17px] font-semibold">{result.price !== null ? <AnimatedNumber value={result.price} from={result.price} duration={400} format={money} /> : "—"}</p>
            </div>
          </>
        )}
      </Card>
    </div>
  );
}
