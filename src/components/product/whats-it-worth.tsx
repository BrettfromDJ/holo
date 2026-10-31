"use client";

import { ChevronDown } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { GradedPrices } from "@/components/grading/grading-items";
import { Badge } from "@/components/ui/badge";
import { Segmented } from "@/components/ui/segmented";
import { loadConditions } from "@/lib/ebay-client";
import type { ConditionPrice } from "@/lib/ebay-types";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money, signedMoney } from "@/lib/format";
import { useGradingCosts } from "@/lib/store/grading";
import { gradedWorth, gradesFor, rawWorth, RAW_CONDITIONS, WORTH_GRADERS, type RawCondition, type Worth, type WorthGrader } from "@/lib/worth";
import { cn } from "@/lib/utils";
import { conditionHue, useEbayData } from "./ebay-sales";

type Mode = "raw" | "graded";

const CONDITION_BY_LABEL: Record<string, RawCondition> = Object.fromEntries(RAW_CONDITIONS.map((c) => [c.label, c.id]));

/**
 * One question, one number: what is this card worth in a given condition or
 * grade? Pick Raw (NM to Damaged) or Graded (company and grade); the price
 * says where it came from, and estimates are always marked as estimates.
 * Opens on the copy you own.
 */
export function WhatsItWorth({ productId, printing, name, nm, owned }: { productId: string; printing: string | null; name: string; nm: number | null; owned: HoldingView[] }) {
  const slab = owned.find((h) => h.identity.grade)?.identity.grade;
  const rawHeld = owned.find((h) => !h.identity.grade);
  const [mode, setMode] = useState<Mode>(slab && !rawHeld ? "graded" : "raw");
  const [condition, setCondition] = useState<RawCondition>(CONDITION_BY_LABEL[rawHeld?.identity.condition ?? ""] ?? "NM");
  const [company, setCompany] = useState<WorthGrader>((WORTH_GRADERS as readonly string[]).includes(slab?.company ?? "") ? (slab!.company as WorthGrader) : "PSA");
  const [grade, setGrade] = useState<string>(slab?.grade ?? "10");
  const [table, setTable] = useState(false);
  const { costs } = useGradingCosts();
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

  const grades = gradesFor(company);
  const gradeNow = grades.includes(grade) ? grade : "10";
  const worth: Worth | null = useMemo(() => {
    if (nm === null) return null;
    return mode === "raw" ? rawWorth(nm, condition, ebay, conditions, printing) : gradedWorth(productId, nm, { company, grade: gradeNow }, ebay, null, sampleMode);
  }, [nm, mode, condition, ebay, productId, company, gradeNow, sampleMode, conditions, printing]);
  const gem = nm === null ? null : gradedWorth(productId, nm, { company: "PSA", grade: "10" }, ebay, null, sampleMode);

  if (nm === null || !worth) return null;
  const vsNm = worth.price - nm;
  const label = mode === "raw" ? RAW_CONDITIONS.find((c) => c.id === condition)!.label : `${company} ${gradeNow}`;
  const yours = mode === "raw" ? rawHeld && CONDITION_BY_LABEL[rawHeld.identity.condition] === condition : slab && slab.company === company && slab.grade === gradeNow;
  const estimate = worth.source === "estimate";
  const gradingGain = gem ? gem.price - nm - costs.fee - costs.shipping : null;

  return (
    <>
      <section className="mt-6 rounded-[var(--radius-card)] border border-border bg-surface p-5 sm:p-6">
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-[15px] font-semibold">What&apos;s it worth?</h2>
          {sampleMode && <Badge variant="sample">Sample data</Badge>}
        </div>

        <div className="mt-3">
          <Segmented
            ariaLabel="Raw or graded"
            size="sm"
            value={mode}
            onChange={setMode}
            options={[
              { value: "raw", label: "Raw" },
              { value: "graded", label: "Graded" },
            ]}
          />
        </div>

        {/* The answer */}
        <div className="mt-5 flex items-end justify-between gap-3">
          <p className={cn("hype-num tabular text-[clamp(40px,12vw,56px)] leading-none", estimate && "text-foreground/85")}>
            {money(worth.price)}
          </p>
          <span className="mb-1 shrink-0 text-right">
            <span className="block text-[14px] font-semibold">{label}</span>
            {yours && <span className="block text-[11px] text-muted">Yours</span>}
          </span>
        </div>
        <SourceLine worth={worth} />
        {!(mode === "raw" && condition === "NM") && (
          <p className="tabular mt-1 text-[12px] text-muted">
            <span className={vsNm >= 0 ? "text-up" : "text-down"}>{signedMoney(vsNm)}</span> vs raw Near Mint ({money(nm)})
          </p>
        )}

        {/* The picker */}
        {mode === "raw" ? (
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
        ) : (
          <div className="mt-5">
            <div className="grid grid-cols-5 gap-1.5" role="radiogroup" aria-label="Grading company">
              {WORTH_GRADERS.map((g) => (
                <button
                  key={g}
                  type="button"
                  role="radio"
                  aria-checked={company === g}
                  onClick={() => setCompany(g)}
                  className={cn("h-10 rounded-xl text-[13px] font-semibold transition-colors", company === g ? "bg-foreground text-background" : "bg-surface-2 text-muted hover:text-foreground")}
                >
                  {g}
                </button>
              ))}
            </div>
            <div className="mt-4">
              <input
                type="range"
                min={0}
                max={grades.length - 1}
                step={1}
                value={grades.indexOf(gradeNow)}
                onChange={(e) => setGrade(grades[Number(e.target.value)])}
                aria-label={`${company} grade`}
                aria-valuetext={`${company} ${gradeNow}`}
                className="deal-range w-full"
              />
              <div className="mt-1.5 flex justify-between font-mono text-[10px] text-subtle" aria-hidden>
                {grades.map((g) => (
                  <button key={g} type="button" onClick={() => setGrade(g)} className={cn("w-5 text-center", g === gradeNow && "font-bold text-foreground", g.includes(".") && "hidden sm:block")}>
                    {g}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* Is grading it worth it? */}
        {mode === "raw" && gem && gradingGain !== null && (
          <button
            type="button"
            onClick={() => {
              setMode("graded");
              setCompany("PSA");
              setGrade("10");
            }}
            className="mt-5 flex w-full items-center justify-between gap-3 rounded-2xl bg-surface-2 px-4 py-3 text-left transition-colors hover:bg-surface-3"
          >
            <span className="min-w-0 text-[13px] text-muted">
              As a PSA 10: <span className="tabular font-semibold text-foreground">{gem.source === "estimate" ? "≈ " : ""}{money(gem.price)}</span>
            </span>
            <span className="tabular shrink-0 text-[13px] text-muted">
              <span className={gradingGain >= 0 ? "text-up" : "text-down"}>{signedMoney(gradingGain)}</span> after grading
            </span>
          </button>
        )}

        <button type="button" onClick={() => setTable((v) => !v)} aria-expanded={table} className="mt-4 flex items-center gap-1 text-[12px] font-medium text-muted hover:text-foreground">
          Full graded price table <ChevronDown className={cn("size-3.5 transition-transform", table && "rotate-180")} />
        </button>
      </section>
      {table && <GradedPrices productId={productId} printing={printing} owned={owned.flatMap((h) => (h.identity.grade ? [h.identity.grade] : []))} />}
    </>
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
