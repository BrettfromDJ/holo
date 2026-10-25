"use client";

import { ArrowRight } from "lucide-react";
import Link from "next/link";
import { useMemo } from "react";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { useInView } from "@/components/motion/reveal";
import {
  holdingHref,
  holdingLabel,
} from "@/components/portfolio/holding-items";
import { Delta } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import type {
  HoldingView,
  PortfolioSummary,
  RangePerformance as Performance,
} from "@/lib/finance/portfolio";
import { formatDate, money, signedMoney, signedPct } from "@/lib/format";
import { cn } from "@/lib/utils";

/* ---------------------------- Movers board ----------------------------- */

export type Mover = { h: HoldingView; m: number };

/** Dollar move implied by a % move over the period, from today's value. */
function dollarMove(h: HoldingView, m: number, daily: boolean) {
  if (daily && h.dayChange !== null) return h.dayChange;
  if (h.value === null) return null;
  return h.value - h.value / (1 + m);
}

/**
 * Diverging bar board: one shared zero line, gains grow right in green,
 * losses grow left in red, each bar sized against the period's biggest move.
 */
export function MoversBoard({
  gainers,
  losers,
  daily,
}: {
  gainers: Mover[];
  losers: Mover[];
  daily: boolean;
}) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const rows = useMemo(
    () => [...gainers, ...[...losers].reverse()],
    [gainers, losers],
  );
  const max = useMemo(
    () => Math.max(...rows.map((r) => Math.abs(r.m)), 0.0001),
    [rows],
  );

  if (!rows.length) {
    return (
      <div className="rounded-[var(--radius-card)] border border-border bg-surface px-6 py-10 text-center text-[14px] text-muted">
        Nothing moved in this period.
      </div>
    );
  }

  return (
    <div
      ref={ref}
      className="relative overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface p-3 sm:p-4"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute inset-y-0 left-0 w-1/2 opacity-60"
        style={{
          background:
            "radial-gradient(60% 80% at 0% 0%, color-mix(in srgb, var(--down) 8%, transparent), transparent)",
        }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-y-0 right-0 w-1/2 opacity-60"
        style={{
          background:
            "radial-gradient(60% 80% at 100% 0%, color-mix(in srgb, var(--up) 8%, transparent), transparent)",
        }}
      />
      <ol className="relative">
        {rows.map(({ h, m }, i) => {
          const up = m > 0;
          const width = (Math.abs(m) / max) * 100;
          const firstLoser = !up && i > 0 && rows[i - 1].m > 0;
          const usd = dollarMove(h, m, daily);
          return (
            <li
              key={h.key}
              className={cn(
                firstLoser && "mt-2 border-t border-dashed border-border pt-2",
              )}
            >
              <Link
                href={holdingHref(h)}
                className="group grid grid-cols-[2.75rem_minmax(0,1fr)_auto] items-center gap-x-3 gap-y-2 rounded-2xl px-2 py-2.5 transition-colors hover:bg-surface-2/70 sm:grid-cols-[2.75rem_minmax(0,1fr)_minmax(0,1.15fr)_5.5rem] sm:gap-x-4"
              >
                <ProductImage
                  product={h.product}
                  size="xs"
                  className="size-11 rounded-xl transition-transform duration-500 group-hover:scale-110 group-hover:-rotate-3"
                />
                <div className="min-w-0">
                  <p className="truncate text-[14px] font-medium">
                    {h.product?.name ?? "Unknown product"}
                  </p>
                  <p className="tabular truncate text-[12px] text-muted">
                    {money(h.value)}
                    {h.quantity > 1 && <span> · ×{h.quantity}</span>}
                    {holdingLabel(h) && <span> · {holdingLabel(h)}</span>}
                  </p>
                </div>

                {/* Diverging track */}
                <div
                  className="relative col-span-3 -mt-1 h-4 sm:col-span-1 sm:mt-0 sm:h-7"
                  aria-hidden
                >
                  <div className="absolute inset-y-0 left-1/2 w-px bg-border" />
                  <div
                    className={cn(
                      "absolute top-1/2 h-3 -translate-y-1/2 rounded-full",
                      up
                        ? "left-1/2 origin-left rounded-l-none"
                        : "right-1/2 origin-right rounded-r-none",
                      inView ? "animate-grow-x" : "scale-x-0",
                    )}
                    style={{
                      width: `${width / 2}%`,
                      background: up
                        ? "linear-gradient(90deg, color-mix(in srgb, var(--up) 35%, transparent), var(--up))"
                        : "linear-gradient(270deg, color-mix(in srgb, var(--down) 35%, transparent), var(--down))",
                      boxShadow: `0 0 18px color-mix(in srgb, var(${up ? "--up" : "--down"}) 35%, transparent)`,
                      animationDelay: `${120 + i * 60}ms`,
                    }}
                  />
                </div>

                <div className="col-start-3 row-start-1 text-right sm:col-start-4">
                  <p
                    className={cn(
                      "tabular text-[15px] font-semibold",
                      up ? "text-up" : "text-down",
                    )}
                  >
                    {signedPct(m)}
                  </p>
                  <p className="tabular text-[12px] text-muted">
                    {usd === null ? "—" : signedMoney(usd)}
                  </p>
                </div>
              </Link>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

/* ------------------------- Performance panel --------------------------- */

export function PerformancePanel({
  summary,
  holdings,
  yearPerf,
  allTime,
}: {
  summary: PortfolioSummary;
  holdings: HoldingView[];
  yearPerf: Performance | null;
  allTime: Performance | null;
}) {
  const drivers = useMemo(
    () =>
      [...holdings]
        .filter((h) => h.unrealized)
        .sort(
          (a, b) => Math.abs(b.unrealized ?? 0) - Math.abs(a.unrealized ?? 0),
        )
        .slice(0, 3),
    [holdings],
  );
  const driverMax = Math.max(
    ...drivers.map((h) => Math.abs(h.unrealized ?? 0)),
    1,
  );
  const total = summary.unrealized + summary.realized;
  const totalPct = summary.costBasis > 0 ? total / summary.costBasis : null;

  return (
    <Link
      href="/gains"
      className="group flex min-w-0 flex-col rounded-[var(--radius-card)] border border-border bg-surface p-6 transition-colors hover:bg-surface-2/50 sm:p-7"
    >
      <div className="flex items-center justify-between">
        <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-muted">
          Total return
        </p>
        <span className="flex items-center gap-1 text-[13px] font-medium text-muted transition-colors group-hover:text-foreground">
          Breakdown{" "}
          <ArrowRight className="size-3.5 transition-transform group-hover:translate-x-0.5" />
        </span>
      </div>
      <p className="tabular mt-3 text-[44px] font-semibold leading-none tracking-[-0.04em] sm:text-[52px]">
        <AnimatedNumber value={total} format={signedMoney} duration={1200} />
      </p>
      <p className="tabular mt-2.5 text-[13px] text-muted">
        <Delta ratio={totalPct} pctOnly className="font-medium" /> on{" "}
        {money(summary.costBasis)} invested
      </p>
      <p className="tabular mt-1 text-[13px] text-subtle">
        {signedMoney(summary.unrealized)} unrealized ·{" "}
        {signedMoney(summary.realized)} realized
      </p>

      {drivers.length > 0 && (
        <div className="mt-8 border-t border-border pt-5">
          <p className="mb-3 text-[11px] font-semibold uppercase tracking-[0.12em] text-subtle">
            Biggest drivers
          </p>
          <ul className="space-y-3">
            {drivers.map((h, i) => {
              const v = h.unrealized ?? 0;
              return (
                <li key={h.key}>
                  <div className="flex items-baseline justify-between gap-3">
                    <p className="truncate text-[13px] text-foreground/85">
                      {h.product?.name}
                    </p>
                    <span className="tabular shrink-0 text-[13px] font-medium">
                      {signedMoney(v)}
                    </span>
                  </div>
                  <div className="mt-1.5 h-[3px] overflow-hidden rounded-full bg-surface-2">
                    <div
                      className="h-full origin-left animate-grow-x rounded-full bg-foreground/35"
                      style={{
                        width: `${(Math.abs(v) / driverMax) * 100}%`,
                        animationDelay: `${300 + i * 120}ms`,
                      }}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
        </div>
      )}

      <div className="mt-auto pt-8">
        <dl className="grid grid-cols-2 gap-6 border-t border-border pt-5">
          <Stat label="Time-weighted, 1Y" ratio={yearPerf?.twr ?? null} />
          <Stat
            label={
              allTime
                ? `Since ${formatDate(allTime.start)}`
                : "Time-weighted, all"
            }
            ratio={allTime?.twr ?? null}
          />
        </dl>
      </div>
    </Link>
  );
}

function Stat({ label, ratio }: { label: string; ratio: number | null }) {
  return (
    <div className="min-w-0">
      <dt className="truncate text-[12px] text-muted">{label}</dt>
      <dd className="tabular mt-1 text-[17px] font-semibold">
        {signedPct(ratio)}
      </dd>
    </div>
  );
}

/* -------------------------- Recently added ----------------------------- */

/** Vertical timeline of the latest additions, newest first. */
export function RecentTimeline({ holdings }: { holdings: HoldingView[] }) {
  const [ref, inView] = useInView<HTMLOListElement>();
  return (
    <div className="min-w-0 rounded-[var(--radius-card)] border border-border bg-surface p-6 sm:p-7">
      <div className="mb-5 flex items-center justify-between">
        <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-muted">
          Recently added
        </p>
        <Link
          href="/activity"
          className="flex items-center gap-1 text-[13px] font-medium text-muted hover:text-foreground"
        >
          Activity <ArrowRight className="size-3.5" />
        </Link>
      </div>
      <ol ref={ref} className="relative">
        <span
          aria-hidden
          className={cn(
            "absolute bottom-6 left-[5px] top-2 w-px origin-top bg-gradient-to-b from-[var(--cat-1)] via-border to-border",
            inView ? "animate-[grow-y_1s_var(--ease-apple)_both]" : "scale-y-0",
          )}
        />
        {holdings.map((h, i) => (
          <li
            key={h.key}
            className={cn(
              "relative pl-7",
              inView ? "animate-rise" : "opacity-0",
            )}
            style={{ animationDelay: `${150 + i * 90}ms` }}
          >
            <span
              aria-hidden
              className={cn(
                "absolute left-0 top-[22px] size-[11px] rounded-full border-2 border-surface",
                i === 0
                  ? "bg-[var(--cat-1)] shadow-[0_0_0_4px_color-mix(in_srgb,var(--cat-1)_25%,transparent)]"
                  : "bg-surface-2 ring-1 ring-border",
              )}
            />
            <Link
              href={holdingHref(h)}
              className="group -mx-2 flex items-center gap-3 rounded-2xl px-2 py-2.5 transition-colors hover:bg-surface-2/70"
            >
              <ProductImage
                product={h.product}
                size="xs"
                className="size-12 shrink-0 rounded-xl transition-transform duration-500 group-hover:scale-105"
              />
              <div className="min-w-0 flex-1">
                <p className="text-[11px] font-medium uppercase tracking-wider text-subtle">
                  {formatDate(h.lastAcquired)}
                </p>
                <p className="truncate text-[14px] font-medium">
                  {h.product?.name ?? "Unknown product"}
                </p>
                <p className="tabular truncate text-[12px] text-muted">
                  {h.quantity} × {money(h.avgCost)} paid
                </p>
              </div>
              <div className="shrink-0 text-right">
                <p className="tabular text-[14px] font-semibold">
                  {money(h.value)}
                </p>
                <Delta
                  ratio={h.unrealizedPct}
                  pctOnly
                  className="text-[12px]"
                />
              </div>
            </Link>
          </li>
        ))}
      </ol>
    </div>
  );
}
