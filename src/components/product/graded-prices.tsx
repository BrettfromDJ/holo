"use client";

import { useEffect, useState } from "react";
import { ChevronsUpDown } from "lucide-react";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { useInView } from "@/components/motion/reveal";
import { Card, SectionTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import type { PriceChartingGraded } from "@/lib/graded";
import { money, relativeTime } from "@/lib/format";
import type { Grade } from "@/lib/types";
import { GRADED_ROWS, gradedLookup, gradedPrice, gradedSourceLabel, isEstimate, lookupGrades, WORTH_GRADERS, type WorthGrader } from "@/lib/worth";
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
 * What the card sells for graded. Every row names one company and grade; its price is recent
 * eBay sales of that exact slab when there are enough, else PriceCharting (below 10 scaled to
 * the company, ≈), else the last eBay sale, else the usual grade curve (≈), with a small word
 * saying which. Below it, look up any company and grade the same way. Same as the app's Graded
 * prices panel.
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
  const hasEbayGraded = Boolean(ebay && Object.keys(ebay.graded).length);
  if (pc.ready && !real && !(nm !== null && nm > 0) && !hasEbayGraded) return null;

  const ungraded = real?.ungraded ?? nm;
  const priced = GRADED_ROWS.flatMap((row) => {
    const p = gradedPrice(productId, row, real, ebay, nm);
    return p ? [{ row, p }] : [];
  });
  // "Yours" when you own that exact company and grade.
  const isOwned = (row: (typeof GRADED_ROWS)[number]) => owned.some((g) => g.company.toUpperCase() === row.company && Number(g.grade) === Number(row.grade));
  const result = gradedLookup(productId, nm, { company, grade }, ebay, real);
  const subtitle = !pc.ready
    ? "What it sells for graded"
    : real
      ? `What it sells for graded · eBay and PriceCharting${real.updatedAt ? ` · updated ${relativeTime(real.updatedAt)}` : ""}`
      : hasEbayGraded
        ? "What it sells for graded · eBay"
        : "Estimated from the usual grade curve";

  return (
    <div ref={ref} className={className}>
      <Card className="p-5 sm:p-6">
        <SectionTitle title="Graded prices" subtitle={subtitle} />
        {!pc.ready ? (
          <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-10 w-full rounded-xl" />
            ))}
          </div>
        ) : (
          <>
            {ungraded !== null && (
              <div className="mb-2 flex items-baseline justify-between rounded-xl bg-surface-2 px-4 py-3">
                <span className="text-[13px] text-muted">Ungraded</span>
                <span className="tabular text-[17px] font-semibold">{money(ungraded)}</span>
              </div>
            )}
            {priced.length > 0 && (
              <>
                <ul className="divide-y divide-border">
                  {priced.map(({ row, p }) => {
                    const mine = isOwned(row);
                    return (
                      // The wash sits behind the row and reaches past it, so the row's content stays in line with the others.
                      <li key={`${row.company} ${row.grade}`} className="relative flex items-center gap-2.5 py-3">
                        {mine && <span aria-hidden className="absolute -inset-x-3 inset-y-0 rounded-xl bg-[color-mix(in_srgb,var(--lime)_10%,transparent)]" />}
                        <span className="relative inline-flex min-w-[4.5rem] items-center gap-1 rounded-[6px] bg-surface-2 px-2 py-1 font-mono text-[12px] font-medium leading-none ring-1 ring-inset ring-border">
                          <span className="text-muted">{row.company}</span>
                          <span className="text-foreground">{row.grade}</span>
                        </span>
                        {mine && <span className="relative text-[11px] font-semibold text-[var(--lime)]">Yours</span>}
                        <span className="relative ml-auto text-[12px] text-subtle">{gradedSourceLabel(p.source)}</span>
                        <span className="relative tabular min-w-24 text-right text-[16px] font-semibold">
                          {isEstimate(p.source) ? "≈ " : ""}
                          {money(p.value)}
                        </span>
                      </li>
                    );
                  })}
                </ul>
                <p className="mt-3 text-[12px] text-subtle">
                  eBay: the median of this month&apos;s sales of that exact slab. ≈: an estimate, from PriceCharting&apos;s price for the grade (which mixes every company) adjusted for the company, or from the usual grade curve.
                </p>
              </>
            )}
            <div className="my-5 h-px bg-border" />

            {/* Look up any grade: two small menus, the price beside them, where it comes from underneath. */}
            <p className="font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">Look up any grade</p>
            <div className="mt-2.5 flex items-center gap-2">
              <LookupMenu
                label="Grading company"
                value={company}
                options={WORTH_GRADERS}
                onChange={(c) => {
                  const next = c as WorthGrader;
                  setCompany(next);
                  if (!lookupGrades(next).includes(grade)) setGrade("10");
                }}
              />
              <LookupMenu label={`${company} grade`} value={grade} options={lookupGrades(company)} onChange={setGrade} />
              <p className="tabular ml-auto shrink-0 font-display text-[24px] font-semibold tracking-[-0.025em]" aria-live="polite">
                {result.price !== null ? <AnimatedNumber value={result.price} from={result.price} duration={400} format={money} /> : "—"}
              </p>
            </div>
            <p className="mt-2.5 line-clamp-2 text-[12px] text-subtle">{result.detail}</p>
          </>
        )}
      </Card>
    </div>
  );
}

/** A small pill showing the current choice; click it for the list. */
function LookupMenu({ label, value, options, onChange }: { label: string; value: string; options: readonly string[]; onChange: (v: string) => void }) {
  return (
    <span className="relative inline-flex h-9 items-center rounded-full bg-surface-2 ring-1 ring-inset ring-border transition-colors hover:bg-foreground/[0.08]">
      <select
        aria-label={label}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="tabular h-full cursor-pointer appearance-none rounded-full bg-transparent py-0 pl-3.5 pr-8 text-[15px] font-semibold text-foreground outline-none focus-visible:ring-2 focus-visible:ring-[var(--lime)]"
      >
        {options.map((o) => (
          <option key={o} value={o} className="bg-surface text-foreground">
            {o}
          </option>
        ))}
      </select>
      <ChevronsUpDown aria-hidden className="pointer-events-none absolute right-3 size-3 text-muted" strokeWidth={2.5} />
    </span>
  );
}
