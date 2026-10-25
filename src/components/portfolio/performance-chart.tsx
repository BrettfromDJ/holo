"use client";

import { Info } from "lucide-react";
import { useMemo, useState } from "react";
import { ScrubChart } from "@/components/charts/scrub-chart";
import { Delta } from "@/components/product/delta";
import { Segmented } from "@/components/ui/segmented";
import { Hint } from "@/components/ui/tooltip";
import { performanceOf, slicePoints, type TimelinePoint } from "@/lib/finance/portfolio";
import { formatDate, money, tone } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import type { ChartRange } from "@/lib/types";

export const RANGES: ChartRange[] = ["1D", "1W", "1M", "3M", "1Y", "ALL"];
export const RANGE_LABEL: Record<ChartRange, string> = {
  "1D": "Today",
  "1W": "Past week",
  "1M": "Past month",
  "3M": "Past 3 months",
  "1Y": "Past year",
  ALL: "All time",
};

/**
 * Portfolio value over time. The change shown is market performance only:
 * dollar change sums cash-flow-adjusted daily gains, and the percentage is a
 * time-weighted return — buying or selling inventory never moves it.
 */
export function PerformanceChart({ timeline, header }: { timeline: TimelinePoint[]; header?: (scrub: { value: number; date: string } | null) => React.ReactNode }) {
  const { today, data, savePreferences } = useStore();
  const [range, setRange] = useState<ChartRange>(data.preferences.chartRange);
  const [scrub, setScrub] = useState<number | null>(null);
  const [showInvested, setShowInvested] = useState(false);

  const slice = useMemo(() => slicePoints(timeline, range, today), [timeline, range, today]);
  const chartData = useMemo(() => slice.map((p) => ({ date: p.date, value: p.value, secondary: showInvested ? p.costBasisPriced : undefined })), [slice, showInvested]);

  const upto = scrub !== null && scrub < slice.length ? slice.slice(0, scrub + 1) : slice;
  const perf = performanceOf(upto);
  const point = upto[upto.length - 1];
  const t = tone(performanceOf(slice)?.marketGain ?? 0);

  return (
    <div>
      {header?.(scrub !== null && point ? { value: point.value, date: point.date } : null)}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex min-h-6 items-center gap-2 text-[14px]">
          {perf ? (
            <>
              <Delta value={perf.marketGain} ratio={perf.twr} className="font-medium" />
              <span className="text-muted">{scrub !== null && point ? formatDate(point.date) : RANGE_LABEL[range]}</span>
              <Hint content="Market performance only. Purchases and sales are excluded; the percentage is a time-weighted return.">
                <button aria-label="How performance is calculated" className="text-subtle hover:text-muted">
                  <Info className="size-3.5" />
                </button>
              </Hint>
            </>
          ) : (
            <span className="text-muted">No history yet</span>
          )}
        </div>
        <div className="flex items-center gap-3">
          <label className="flex cursor-pointer items-center gap-2 text-[12px] text-muted">
            <input type="checkbox" checked={showInvested} onChange={(e) => setShowInvested(e.target.checked)} className="size-3.5 accent-[var(--foreground)]" />
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-0 w-4 border-t-[1.5px] border-dashed border-subtle" aria-hidden />
              Cost basis
            </span>
          </label>
          <Segmented
            ariaLabel="Chart range"
            size="sm"
            value={range}
            onChange={(r) => {
              setRange(r);
              void savePreferences({ chartRange: r });
            }}
            options={RANGES.map((r) => ({ value: r, label: r }))}
          />
        </div>
      </div>
      <div className="relative mt-4">
        {slice.length > 1 && (
          // Ambient glow tinted by performance; purely decorative.
          <div
            aria-hidden
            className="pointer-events-none absolute -inset-x-10 -bottom-6 top-6 -z-0 rounded-[50%] opacity-80 blur-3xl transition-colors duration-700"
            style={{
              background: `radial-gradient(60% 55% at 70% 55%, color-mix(in srgb, ${t === "down" ? "var(--down)" : t === "up" ? "var(--up)" : "var(--muted)"} 16%, transparent), transparent 70%)`,
            }}
          />
        )}
        {slice.length > 1 ? (
          <ScrubChart data={chartData} tone={t} baseline={slice[0]?.value} onScrub={setScrub} height={300} secondaryLabel="Cost basis" className="relative" />
        ) : (
          <div className="flex h-[280px] items-center justify-center rounded-2xl border border-dashed border-border text-[14px] text-muted">
            The chart fills in as daily price snapshots accumulate.
          </div>
        )}
      </div>
      {slice.length > 1 && (
        <p className="mt-2 text-right text-[11px] text-subtle">
          Daily closing values{range === "1D" ? " · intraday prices aren't available" : ""} · {money(slice[0].value)} on {formatDate(slice[0].date)}
        </p>
      )}
    </div>
  );
}
