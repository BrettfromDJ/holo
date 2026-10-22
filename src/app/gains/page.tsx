"use client";

import { AlertCircle } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { CATEGORY_META } from "@/components/portfolio/allocation-bar";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { Delta } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
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
      <PageHeader title="Gains" subtitle="See exactly which products your gains come from." actions={store.mode === "demo" ? <Badge variant="sample">Sample data</Badge> : undefined} />

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
        <div className="flex flex-wrap items-end justify-between gap-6">
          <div>
            <p className="text-[13px] font-medium text-muted">{MODE_LABEL[mode]}</p>
            <p className="tabular mt-1 text-[40px] font-semibold leading-none tracking-[-0.03em] sm:text-[48px]">
              <Delta value={total} />
            </p>
            <p className="mt-2 text-[13px] text-subtle">{MODE_HINT[mode]}</p>
          </div>
          <dl className="grid grid-cols-2 gap-x-8 gap-y-1 text-[13px] sm:text-right">
            <dt className="text-muted">
              Gains · {winners} {winners === 1 ? noun.replace(/s$/, "").replace(/ie$/, "y") : noun}
            </dt>
            <dd className={cn("tabular font-semibold", gains > 0 ? "text-up" : "text-muted")}>{gains > 0 ? signedMoney(gains) : money(0)}</dd>
            <dt className="text-muted">
              Losses · {losers} {losers === 1 ? noun.replace(/s$/, "").replace(/ie$/, "y") : noun}
            </dt>
            <dd className={cn("tabular font-semibold", losses < 0 ? "text-down" : "text-muted")}>{losses < 0 ? signedMoney(losses) : money(0)}</dd>
          </dl>
        </div>

        {topThreeShare !== null && winners > 3 && (
          <p className="mt-6 rounded-xl bg-surface-2 px-4 py-3 text-[14px]">
            Your top 3 {noun} account for <span className="font-semibold text-foreground">{pct(topThreeShare, 0)}</span> of your gains.
          </p>
        )}

        {!steps.length ? (
          <p className="py-16 text-center text-[14px] text-muted">{mode === "realized" ? "No sales or write-offs yet." : "No gains or losses yet."}</p>
        ) : (
          <div className="mt-8">
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
    <div className="relative col-span-2 h-6 sm:col-span-1" aria-hidden>
      <div className="absolute inset-y-[11px] left-0 right-0 rounded-full bg-surface-2" />
      <div className="absolute inset-y-0 w-px bg-border-strong" style={{ left: `${pos(0)}%` }} />
      <div
        className={cn("absolute inset-y-1 rounded-[4px] transition-all duration-500 ease-[var(--ease-apple)]", total ? "bg-foreground" : up ? "bg-up" : "bg-down")}
        style={{ left: `${left}%`, width: `${width}%` }}
      />
    </div>
  );
}
