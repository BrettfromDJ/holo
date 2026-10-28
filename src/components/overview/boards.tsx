"use client";

import { ArrowRight } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { useInView } from "@/components/motion/reveal";
import {
  holdingHref,
  holdingLabel,
} from "@/components/portfolio/holding-items";
import { Delta } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import type { HoldingView } from "@/lib/finance/portfolio";
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

const COLLAPSED = 3;

/**
 * Two compact columns, gainers and losers, each sized against the period's
 * biggest move so bars compare across both. Shows the top few with the rest
 * a click away.
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
  const max = useMemo(
    () => Math.max(...[...gainers, ...losers].map((r) => Math.abs(r.m)), 0.0001),
    [gainers, losers],
  );

  if (!gainers.length && !losers.length) {
    return (
      <div className="rounded-[var(--radius-card)] border border-border bg-surface px-6 py-10 text-center text-[14px] text-muted">
        Nothing moved in this period.
      </div>
    );
  }

  return (
    <div ref={ref} className="grid gap-3 lg:grid-cols-2">
      <MoverColumn title="Gainers" rows={gainers} up max={max} daily={daily} inView={inView} />
      <MoverColumn title="Losers" rows={[...losers].sort((a, b) => a.m - b.m)} up={false} max={max} daily={daily} inView={inView} />
    </div>
  );
}

function MoverColumn({ title, rows, up, max, daily, inView }: { title: string; rows: Mover[]; up: boolean; max: number; daily: boolean; inView: boolean }) {
  const [all, setAll] = useState(false);
  const shown = all ? rows : rows.slice(0, COLLAPSED);
  return (
    <div className="relative overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface p-2 sm:p-3">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-60"
        style={{ background: `radial-gradient(60% 70% at ${up ? "100%" : "0%"} 0%, color-mix(in srgb, var(${up ? "--up" : "--down"}) 8%, transparent), transparent)` }}
      />
      <p className="relative px-2 pb-1 pt-1 font-mono text-[11px] font-medium uppercase tracking-[0.06em] text-subtle">
        {title}
        {rows.length > 0 && <span className="ml-1.5 text-subtle/70">{rows.length}</span>}
      </p>
      {rows.length ? (
        <ol className="relative">
          {shown.map(({ h, m }, i) => {
            const usd = dollarMove(h, m, daily);
            return (
              <li key={h.key}>
                <Link
                  href={holdingHref(h)}
                  className="group grid grid-cols-[2.25rem_minmax(0,1fr)_4.75rem] items-center gap-x-3 rounded-xl px-2 py-1.5 transition-colors hover:bg-surface-2/70 sm:grid-cols-[2.25rem_minmax(0,1fr)_5rem_5rem]"
                >
                  <ProductImage
                    product={h.product}
                    grade={h.identity.grade} slabKey={h.key}
                    size="xs"
                    className="size-9 rounded-lg transition-transform duration-500 group-hover:scale-110 group-hover:-rotate-3"
                  />
                  <div className="min-w-0">
                    <p className="truncate text-[13px] font-medium">{h.product?.name ?? "Unknown product"}</p>
                    <p className="tabular truncate text-[11px] text-muted">
                      {money(h.value)}
                      {h.quantity > 1 && <span> · ×{h.quantity}</span>}
                      {holdingLabel(h) && <span> · {holdingLabel(h)}</span>}
                    </p>
                  </div>
                  <div className="relative hidden h-1.5 overflow-hidden rounded-full bg-surface-2 sm:block" aria-hidden>
                    <div
                      className={cn("absolute inset-y-0 left-0 origin-left rounded-full", inView ? "animate-grow-x" : "scale-x-0")}
                      style={{
                        width: `${(Math.abs(m) / max) * 100}%`,
                        background: `linear-gradient(90deg, color-mix(in srgb, var(${up ? "--up" : "--down"}) 35%, transparent), var(${up ? "--up" : "--down"}))`,
                        boxShadow: `0 0 12px color-mix(in srgb, var(${up ? "--up" : "--down"}) 35%, transparent)`,
                        animationDelay: `${120 + i * 60}ms`,
                      }}
                    />
                  </div>
                  <div className="text-right leading-tight">
                    <p className={cn("tabular text-[13px] font-semibold", up ? "text-up" : "text-down")}>{signedPct(m)}</p>
                    <p className="tabular text-[11px] text-muted">{usd === null ? "—" : signedMoney(usd)}</p>
                  </div>
                </Link>
              </li>
            );
          })}
        </ol>
      ) : (
        <p className="relative px-2 py-4 text-[13px] text-muted">{up ? "Nothing went up in this period." : "Nothing went down in this period."}</p>
      )}
      {rows.length > COLLAPSED && (
        <button type="button" onClick={() => setAll((v) => !v)} className="relative mt-1 px-2 pb-1 text-[12px] font-medium text-muted hover:text-foreground">
          {all ? "Show fewer" : `Show all ${rows.length}`}
        </button>
      )}
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
        <p className="text-[11px] font-medium font-mono uppercase tracking-[0.06em] text-muted">
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
                <p className="text-[11px] font-medium font-mono uppercase tracking-[0.06em] text-subtle">
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
