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
import { isCgcTenGrade } from "@/lib/pristine";
import { GRADED_ROWS, gradedLookup, gradedPrice, gradedSourceLabel, gradeTitle, isEstimate, lookupGrades, PRISTINE_10, rowGradeTitle, WORTH_GRADERS, type GradedRow, type WorthGrader } from "@/lib/worth";
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

/* ------------------------ One grade, under the price ---------------------- */

/**
 * Under a card's headline (its Near Mint, ungraded price): one graded price, PSA 10 to begin with
 * (or the grade of a slab you own), and a menu to pick any company and grade. Priced the same way
 * as the Graded prices panel. Same as the app's GradedPriceLine.
 */
export function GradedPriceLine({ productId, printing, nm, initial, className }: { productId: string; printing: string | null; nm: number | null; initial?: (Grade & { pristine?: boolean }) | null; className?: string }) {
  const pc = usePriceChartingGraded(productId);
  const { load } = useEbayData(productId, printing, { market: nm, active: productId.startsWith("tcgapi:") });
  const ebay = load.state === "ready" ? load.data : null;
  const start = initial ? `${initial.company}|${initial.pristine && isCgcTenGrade(initial.company, initial.grade) ? PRISTINE_10 : initial.grade}` : "PSA|10";
  const [choice, setChoice] = useState(start);
  const [company, grade] = choice.split("|") as [WorthGrader, string];
  const pristine = grade === PRISTINE_10;
  const r = gradedLookup(productId, nm, { company, grade: pristine ? "10" : grade }, ebay, pc.data, pristine);
  const ready = pc.ready && load.state !== "loading";
  return (
    <div className={className}>
      <div className="flex items-center gap-3 rounded-2xl border border-border bg-surface py-2.5 pl-2.5 pr-4">
        <label className="relative inline-flex h-9 items-center gap-1.5 rounded-full bg-[var(--foreground)]/[0.07] pl-3.5 pr-8 text-[14px] font-semibold ring-1 ring-inset ring-[var(--border-strong)]">
          {company} {pristine ? PRISTINE_10 : gradeTitle(company, grade)}
          <ChevronsUpDown className="pointer-events-none absolute right-3 size-3.5 text-muted" aria-hidden />
          <select aria-label="Grade" value={choice} onChange={(e) => setChoice(e.target.value)} className="absolute inset-0 cursor-pointer opacity-0">
            {WORTH_GRADERS.map((c) => (
              <optgroup key={c} label={c}>
                {lookupGrades(c).map((g) => (
                  <option key={g} value={`${c}|${g}`}>
                    {c} {g === PRISTINE_10 ? g : gradeTitle(c, g)}
                  </option>
                ))}
              </optgroup>
            ))}
          </select>
        </label>
        <span className="ml-auto tabular font-display text-[22px] leading-none">
          {!ready ? <Skeleton className="h-6 w-24 rounded-md" /> : r.price != null ? `${r.source && isEstimate(r.source) ? "≈ " : ""}${money(r.price)}` : "—"}
        </span>
      </div>
      {ready && <p className="mt-1.5 text-[12px] text-subtle">{r.detail}</p>}
    </div>
  );
}

/* ------------------------------- The panel -------------------------------- */

/**
 * What the card sells for graded. Every row names one company and grade; its price is recent
 * eBay sales of that exact slab when there are enough, else PriceCharting (below 10 scaled to
 * the company, ≈), else the last eBay sale, else the usual grade curve (≈), with a small word
 * saying which. CGC's 10 is two rows: Pristine 10 (sales whose title says pristine, else ≈ the
 * Gem Mint 10 × the usual premium) and Gem Mint 10. Below it, look up any company and grade the
 * same way. Same as the app's Graded prices panel.
 */
export function GradedPrices({ productId, printing, nm, owned, className }: { productId: string; printing: string | null; nm: number | null; owned: (Grade & { pristine?: boolean })[]; className?: string }) {
  const pc = usePriceChartingGraded(productId);
  const [ref, inView] = useInView<HTMLDivElement>("0px 0px 200px 0px");
  const { load } = useEbayData(productId, printing, {
    market: nm,
    active: inView && productId.startsWith("tcgapi:"),
  });
  const ebay = load.state === "ready" ? load.data : null;

  const slab = owned[0];
  const [company, setCompany] = useState<WorthGrader>(() => ((WORTH_GRADERS as readonly string[]).includes(slab?.company.toUpperCase() ?? "") ? (slab!.company.toUpperCase() as WorthGrader) : "PSA"));
  // The lookup's grade; a CGC Pristine 10 is its own choice ("Pristine 10").
  const [grade, setGrade] = useState<string>(() => {
    const g = slab && slab.pristine && isCgcTenGrade(slab.company, slab.grade) ? PRISTINE_10 : (slab?.grade ?? "9");
    return lookupGrades(company).includes(g) ? g : "10";
  });

  const real = pc.data;
  const hasEbayGraded = Boolean(ebay && Object.keys(ebay.graded).length);
  if (pc.ready && !real && !(nm !== null && nm > 0) && !hasEbayGraded) return null;

  const ungraded = real?.ungraded ?? nm;
  const priced = GRADED_ROWS.flatMap((row) => {
    const p = gradedPrice(productId, row, real, ebay, nm, Boolean(row.pristine));
    return p ? [{ row, p }] : [];
  });
  // "Yours" when you own that exact company and grade (and, for a CGC 10, the same kind).
  const isOwned = (row: GradedRow) =>
    owned.some((g) => g.company.toUpperCase() === row.company && Number(g.grade) === Number(row.grade) && (!isCgcTenGrade(g.company, g.grade) || Boolean(g.pristine) === Boolean(row.pristine)));
  const lookupPristine = grade === PRISTINE_10;
  const result = gradedLookup(productId, nm, { company, grade: lookupPristine ? "10" : grade }, ebay, real, lookupPristine);
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
              <div className="flex items-baseline justify-between border-b border-border py-3">
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
                      <li key={`${row.company} ${row.grade}${row.pristine ? " pristine" : ""}`} className="relative flex items-center gap-2.5 py-3">
                        {mine && <span aria-hidden className="absolute -inset-x-3 inset-y-0 rounded-xl bg-[color-mix(in_srgb,var(--lime)_10%,transparent)]" />}
                        <span className="relative inline-flex min-w-[4rem] items-center gap-1 font-mono text-[13px] font-medium leading-none">
                          <span className="text-muted">{row.company}</span>
                          <span className="text-foreground">{rowGradeTitle(row)}</span>
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
                  eBay: the median of this month&apos;s sales of that exact slab (a CGC Pristine 10 is a sale whose title says pristine). ≈: an estimate, from PriceCharting&apos;s price for the grade (which mixes every company) adjusted for the company, from the usual grade curve, or for a Pristine 10, the Gem Mint 10 price × the usual Pristine premium.
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
              <LookupMenu label={`${company} grade`} value={grade} options={lookupGrades(company)} optionLabel={(g) => gradeTitle(company, g)} onChange={setGrade} />
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
function LookupMenu({ label, value, options, optionLabel, onChange }: { label: string; value: string; options: readonly string[]; optionLabel?: (v: string) => string; onChange: (v: string) => void }) {
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
            {optionLabel ? optionLabel(o) : o}
          </option>
        ))}
      </select>
      <ChevronsUpDown aria-hidden className="pointer-events-none absolute right-3 size-3 text-muted" />
    </span>
  );
}
