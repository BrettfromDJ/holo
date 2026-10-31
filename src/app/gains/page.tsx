"use client";

import { AlertCircle } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { CATEGORY_META } from "@/components/portfolio/allocation-bar";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { Delta } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { PageHeader } from "@/components/shell/page-header";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { attributeGains, type GainGroup, type GainMode, type WaterfallStep } from "@/lib/finance/attribution";
import { money, pct, signedMoney } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

const MODE_LABEL: Record<GainMode, string> = { unrealized: "Unrealized gain", realized: "Realized gain", all: "Total gain" };
const MODE_HINT: Record<GainMode, string> = {
  unrealized: "Market value minus cost basis of what you hold today.",
  realized: "Profit or loss locked in by sales and write-offs.",
  all: "Unrealized plus realized — everything your collection has earned.",
};
const COLLAPSED_ROWS = 12;

export default function GainsPage() {
  const store = useStore();
  const { holdings, realized } = usePortfolio();
  const [mode, setMode] = useState<GainMode>("unrealized");
  const [group, setGroup] = useState<GainGroup>("product");
  const [expanded, setExpanded] = useState(false);

  const attribution = useMemo(
    () => attributeGains(holdings, realized, store.data.products, { mode, group, maxRows: expanded ? undefined : COLLAPSED_ROWS }),
    [holdings, realized, store.data.products, mode, group, expanded],
  );
  const fullCount = useMemo(() => attributeGains(holdings, realized, store.data.products, { mode, group }).steps.length, [holdings, realized, store.data.products, mode, group]);

  if (store.status === "loading") return <Skeleton className="h-[600px] w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) {
    return (
      <>
        <PageHeader title="Gains" />
        <EmptyCollection title="No gains to show yet" />
      </>
    );
  }

  const { steps, total, gains, losses, winners, losers, topThreeShare, unpriced } = attribution;
  const extent = steps.reduce((acc, s) => ({ min: Math.min(acc.min, s.start, s.end), max: Math.max(acc.max, s.start, s.end) }), { min: 0, max: 0 });
  const span = extent.max - extent.min || 1;
  const pos = (v: number) => ((v - extent.min) / span) * 100;
  const noun = group === "product" ? "products" : group === "set" ? "sets" : "categories";

  return (
    <div className="animate-fade-in">
      <PageHeader
        title={MODE_LABEL[mode]}
        figure={<span className={total >= 0 ? "text-lime" : "text-[var(--plan-pink)]"}>{signedMoney(total)}</span>}
        note={MODE_HINT[mode]}
        actions={store.mode === "demo" ? <Badge variant="sample">Sample data</Badge> : undefined}
        stats={[
          { label: `Pulling up · ${winners}`, value: gains > 0 ? signedMoney(gains) : money(0), tone: gains > 0 ? "up" : undefined },
          { label: `Pulling down · ${losers}`, value: losses < 0 ? signedMoney(losses) : money(0), tone: losses < 0 ? "down" : undefined },
        ]}
      >
        <TugBar gains={gains} losses={losses} />
      </PageHeader>
      <PortfolioSwitcher compact className="mb-3 lg:hidden" />
      <PortfolioBanner />

      <div className="mb-6 flex flex-wrap items-center gap-2">
        <Segmented
          ariaLabel="Gain type"
          value={mode}
          onChange={setMode}
          options={[
            { value: "unrealized", label: "Unrealized" },
            { value: "realized", label: "Realized" },
            { value: "all", label: "All-time" },
          ]}
        />
        <Segmented
          ariaLabel="Group by"
          value={group}
          onChange={(g) => {
            setGroup(g);
            setExpanded(false);
          }}
          options={[
            { value: "product", label: "Products" },
            { value: "set", label: "Sets" },
            { value: "category", label: "Type" },
          ]}
        />
      </div>

      <Card className="p-5 sm:p-7">
        {topThreeShare !== null && winners > 3 && (
          <p className="rounded-xl bg-surface-2 px-4 py-3 text-[14px]">
            Your top 3 {noun} account for <span className="font-semibold text-foreground">{pct(topThreeShare, 0)}</span> of your gains.
          </p>
        )}

        {!steps.length ? (
          <p className="py-16 text-center text-[14px] text-muted">{mode === "realized" ? "No sales or write-offs yet." : "No gains or losses yet."}</p>
        ) : (
          <div className="mt-6 first:mt-0">
            <div>
              <ul className="space-y-1" aria-label="Gain contributions">
                {steps.map((s) => (
                  <StepRow key={s.key} step={s} pos={pos} group={group} gains={gains} />
                ))}
                <li className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-2 border-t border-border pt-3 sm:grid-cols-[minmax(0,15rem)_minmax(0,1fr)_7.5rem]">
                  <span className="text-[14px] font-semibold">{MODE_LABEL[mode]}</span>
                  <Bar start={0} end={total} pos={pos} total />
                  <span className="tabular col-start-2 row-start-1 text-right text-[15px] font-semibold sm:col-start-3">
                    <Delta value={total} />
                  </span>
                </li>
              </ul>
            </div>
            {fullCount > COLLAPSED_ROWS && (
              <button onClick={() => setExpanded((v) => !v)} className="mt-5 text-[13px] font-medium text-muted hover:text-foreground">
                {expanded ? "Show top contributors only" : `Show all ${fullCount} ${noun}`}
              </button>
            )}
          </div>
        )}
      </Card>

      {unpriced > 0 && mode !== "realized" && (
        <p className="mt-4 flex items-center gap-2 text-[13px] text-muted">
          <AlertCircle className="size-4 shrink-0" />
          {unpriced} holding{unpriced === 1 ? " has" : "s have"} no market price and {unpriced === 1 ? "isn't" : "aren't"} included.
        </p>
      )}
    </div>
  );
}

function StepRow({ step, pos, group, gains }: { step: WaterfallStep; pos: (v: number) => number; group: GainGroup; gains: number }) {
  const share = step.gain > 0 && gains > 0 ? step.gain / gains : null;
  const detail = [
    step.quantity > 0 && step.value > 0 ? `${money(step.value)} value · ${money(step.costBasis)} cost` : null,
    step.realized !== 0 && step.unrealized !== 0 ? `${signedMoney(step.realized)} realized` : step.realized !== 0 && step.quantity === 0 ? "Sold" : null,
    step.members ? "Smaller contributors combined" : null,
  ]
    .filter(Boolean)
    .join(" · ");

  const label = (
    <div className="flex min-w-0 items-center gap-3">
      {group === "category" && step.category ? (
        <span className="size-2.5 shrink-0 rounded-full" style={{ background: CATEGORY_META[step.category].color }} aria-hidden />
      ) : step.key !== "__other" ? (
        <ProductImage product={step.product} size="xs" className="size-10 shrink-0 rounded-lg" />
      ) : (
        <span className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-surface-2 text-[12px] text-muted">+{step.members}</span>
      )}
      <div className="min-w-0">
        <p className="truncate text-[14px] font-medium">{step.label}</p>
        {detail && <p className="tabular truncate text-[12px] text-muted">{detail}</p>}
      </div>
    </div>
  );

  const body = (
    <>
      {label}
      <Bar start={step.start} end={step.end} pos={pos} />
      <div className="col-start-2 row-start-1 text-right sm:col-start-3">
        <Delta value={step.gain} className="block text-[14px] font-medium" />
        {share !== null && <span className="tabular text-[11px] text-subtle">{pct(share, 0)} of gains</span>}
      </div>
    </>
  );

  const cls = "grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-2 rounded-xl px-2 py-2 sm:grid-cols-[minmax(0,15rem)_minmax(0,1fr)_7.5rem] -mx-2";
  return (
    <li>
      {group === "product" && step.product && step.key !== "__other" ? (
        <Link href={`/product/${encodeURIComponent(step.key)}`} className={cn(cls, "transition-colors hover:bg-surface-2")}>
          {body}
        </Link>
      ) : (
        <div className={cls}>{body}</div>
      )}
    </li>
  );
}

/** One waterfall segment from `start` to `end` on the shared scale. */
function Bar({ start, end, pos, total }: { start: number; end: number; pos: (v: number) => number; total?: boolean }) {
  const left = pos(Math.min(start, end));
  const width = Math.max(Math.abs(pos(end) - pos(start)), 0.4);
  const up = end >= start;
  return (
    <div className="relative col-span-2 h-4 sm:col-span-1 sm:h-7" aria-hidden>
      <div className="absolute inset-y-0 w-px bg-border" style={{ left: `${pos(0)}%` }} />
      <div
        className={cn("absolute top-1/2 h-3 -translate-y-1/2 animate-grow-x rounded-full transition-all duration-500 ease-[var(--ease-apple)]", up ? "origin-left" : "origin-right")}
        style={{
          left: `${left}%`,
          width: `${width}%`,
          background: total
            ? "linear-gradient(90deg, color-mix(in srgb, var(--foreground) 35%, transparent), var(--foreground))"
            : up
              ? "linear-gradient(90deg, color-mix(in srgb, var(--up) 35%, transparent), var(--up))"
              : "linear-gradient(270deg, color-mix(in srgb, var(--down) 35%, transparent), var(--down))",
          boxShadow: total ? undefined : `0 0 18px color-mix(in srgb, var(${up ? "--up" : "--down"}) 35%, transparent)`,
        }}
      />
    </div>
  );
}

/** Gains against losses as two thin capsules with a gap, like the app's tug-of-war bar. */
function TugBar({ gains, losses }: { gains: number; losses: number }) {
  const sum = Math.max(gains + Math.abs(losses), 0.01);
  const up = (gains / sum) * 100;
  return (
    <div className="flex h-2.5 gap-[3px]" aria-hidden>
      {gains > 0 && <div className="rounded-full bg-lime shadow-[0_0_8px_color-mix(in_srgb,var(--lime)_50%,transparent)]" style={{ width: `${Math.max(up, 1.5)}%` }} />}
      {losses < 0 && <div className="flex-1 rounded-full bg-[var(--plan-pink)] shadow-[0_0_8px_color-mix(in_srgb,var(--plan-pink)_50%,transparent)]" />}
    </div>
  );
}
