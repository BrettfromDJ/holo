"use client";

import { useEffect, useState } from "react";
import { Card, SectionTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import type { PriceChartingGraded } from "@/lib/graded";
import { money, relativeTime } from "@/lib/format";
import type { Grade } from "@/lib/types";
import { cn } from "@/lib/utils";

/** Grades in the order collectors look for them: the 10s by grader, then any grader below. */
const ROWS: { key: string; company: string | null; grade: string }[] = [
  { key: "PSA 10", company: "PSA", grade: "10" },
  { key: "BGS 10", company: "BGS", grade: "10" },
  { key: "CGC 10", company: "CGC", grade: "10" },
  { key: "SGC 10", company: "SGC", grade: "10" },
  { key: "9.5", company: null, grade: "9.5" },
  { key: "9", company: null, grade: "9" },
  { key: "8", company: null, grade: "8" },
  { key: "7", company: null, grade: "7" },
];

/**
 * What the card sells for graded, from PriceCharting's daily price guide (stored nightly, so
 * free to show): each grade's value and how many times ungraded it is. A grade you own is
 * highlighted. Hidden when PriceCharting has no graded prices for the card.
 */
export function GradedPrices({ productId, owned, className }: { productId: string; owned: Grade[]; className?: string }) {
  const [state, setState] = useState<{ status: "loading" } | { status: "ready"; data: PriceChartingGraded | null }>({ status: "loading" });

  useEffect(() => {
    if (!productId.startsWith("tcgapi:")) {
      setState({ status: "ready", data: null });
      return;
    }
    let cancelled = false;
    setState({ status: "loading" });
    fetch(`/api/graded?ids=${encodeURIComponent(productId)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((body: { graded?: Record<string, PriceChartingGraded> } | null) => {
        if (!cancelled) setState({ status: "ready", data: body?.graded?.[productId] ?? null });
      })
      .catch(() => !cancelled && setState({ status: "ready", data: null }));
    return () => {
      cancelled = true;
    };
  }, [productId]);

  if (state.status === "ready" && (!state.data || !Object.keys(state.data.grades).length)) return null;

  const isOwned = (row: (typeof ROWS)[number]) =>
    owned.some((g) => (row.company ? g.company.toUpperCase() === row.company && Number(g.grade) === 10 : Number(g.grade) === Number(row.grade) && Number(g.grade) !== 10));

  return (
    <Card className={cn("p-5 sm:p-6", className)}>
      <SectionTitle
        title="Graded prices"
        subtitle={state.status === "ready" && state.data ? `What it sells for graded · PriceCharting · updated ${relativeTime(state.data.updatedAt)}` : "What it sells for graded"}
      />
      {state.status === "loading" ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-10 w-full rounded-xl" />
          ))}
        </div>
      ) : (
        state.data && (
          <>
            {state.data.ungraded !== null && (
              <div className="mb-3 flex items-baseline justify-between rounded-xl bg-surface-2 px-4 py-3">
                <span className="text-[13px] text-muted">Ungraded</span>
                <span className="tabular text-[17px] font-semibold">{money(state.data.ungraded)}</span>
              </div>
            )}
            <ul className="divide-y divide-border">
              {ROWS.filter((r) => state.data!.grades[r.key] !== undefined).map((r) => {
                const value = state.data!.grades[r.key];
                const multiple = state.data!.ungraded ? value / state.data!.ungraded : null;
                const mine = isOwned(r);
                return (
                  <li key={r.key} className={cn("flex items-center gap-3 py-3", mine && "-mx-3 rounded-xl bg-[var(--lime)]/10 px-3")}>
                    <span className="inline-flex min-w-[4.5rem] items-center gap-1 rounded-[6px] bg-surface-2 px-2 py-1 font-mono text-[12px] font-medium leading-none ring-1 ring-inset ring-border">
                      <span className="text-muted">{r.company ?? "Any"}</span>
                      <span className="text-foreground">{r.grade}</span>
                    </span>
                    {mine && <span className="text-[11px] font-semibold text-[var(--lime)]">Yours</span>}
                    <span className="ml-auto tabular text-[12px] text-subtle">{multiple ? `${multiple >= 10 ? multiple.toFixed(0) : multiple.toFixed(1)}× ungraded` : ""}</span>
                    <span className="tabular w-24 text-right text-[16px] font-semibold">{money(value)}</span>
                  </li>
                );
              })}
            </ul>
            <p className="mt-3 text-[12px] text-subtle">10s are per grading company; lower grades are for any company.</p>
          </>
        )
      )}
    </Card>
  );
}
