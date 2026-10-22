"use client";

import { ArrowDownLeft, ArrowUpRight, MinusCircle, PencilLine, PlusCircle } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { TransactionActions, partitionHistory } from "@/components/flows/transaction-dialogs";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { Delta } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { acquisitionCost, saleProceeds } from "@/lib/finance/ledger";
import { formatDate, formatMonth, money } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import type { Transaction } from "@/lib/types";
import { cn } from "@/lib/utils";

type Filter = "all" | "purchase" | "sale" | "adjustment";

const ICONS = {
  purchase: { icon: ArrowDownLeft, label: "Purchase" },
  sale: { icon: ArrowUpRight, label: "Sale" },
  adjustmentUp: { icon: PlusCircle, label: "Added" },
  adjustmentDown: { icon: MinusCircle, label: "Removed" },
  correction: { icon: PencilLine, label: "Edit record" },
};

export default function ActivityPage() {
  const store = useStore();
  const { realized } = usePortfolio();
  const [filter, setFilter] = useState<Filter>("all");
  const [showHidden, setShowHidden] = useState(false);

  const { groups, effective, byId, hiddenCount } = useMemo(() => {
    const all = store.data.transactions;
    const { effective, visible, hidden } = partitionHistory(all);
    const byId = new Map(all.map((t) => [t.id, t]));
    const list = (showHidden ? all : visible)
      .filter((t) => filter === "all" || t.type === filter || (showHidden && t.type === "correction"))
      .sort((a, b) => (a.date === b.date ? (a.createdAt < b.createdAt ? 1 : -1) : a.date < b.date ? 1 : -1));
    const groups = new Map<string, Transaction[]>();
    for (const t of list) {
      const m = t.date.slice(0, 7);
      groups.set(m, [...(groups.get(m) ?? []), t]);
    }
    return { groups: [...groups.entries()], effective, byId, hiddenCount: hidden.length };
  }, [store.data.transactions, filter, showHidden]);

  const realizedBySale = useMemo(() => new Map(realized.map((r) => [r.transactionId, r])), [realized]);

  if (store.status === "loading") return <Skeleton className="h-96 w-full rounded-[var(--radius-card)]" />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) {
    return (
      <>
        <PageHeader title="Activity" />
        <EmptyCollection title="No activity yet" />
      </>
    );
  }

  return (
    <div className="animate-fade-in">
      <PageHeader title="Activity" subtitle="Every purchase, sale and adjustment." />
      <div className="scrollbar-none -mx-4 mb-5 flex items-center overflow-x-auto px-4">
        <Segmented
          ariaLabel="Filter activity"
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "All" },
            { value: "purchase", label: "Purchases" },
            { value: "sale", label: "Sales" },
            { value: "adjustment", label: "Adjustments" },
          ]}
        />
        {hiddenCount > 0 && (
          <button onClick={() => setShowHidden((v) => !v)} className="ml-3 text-[13px] font-medium text-subtle hover:text-muted">
            {showHidden ? "Hide" : "Show"} deleted &amp; edit records ({hiddenCount})
          </button>
        )}
      </div>

      <div className="space-y-8">
        {groups.map(([month, txs]) => (
          <section key={month}>
            <h2 className="mb-2 px-1 text-[14px] font-semibold text-muted">{formatMonth(month)}</h2>
            <Card className="divide-y divide-border overflow-hidden">
              {txs.map((t) => {
                const product = store.data.products[t.productId];
                const eff = effective.get(t.id);
                const voided = t.type !== "correction" && !eff;
                const corrected = eff && (eff.unitPrice !== t.unitPrice || eff.quantity !== t.quantity || eff.date !== t.date || eff.fees !== t.fees);
                const shown = eff ?? t;
                const meta = t.type === "adjustment" ? (t.quantity > 0 ? ICONS.adjustmentUp : ICONS.adjustmentDown) : ICONS[t.type];
                const Icon = meta.icon;
                const amount = t.type === "sale" ? saleProceeds(shown) : t.type === "purchase" || (t.type === "adjustment" && t.quantity > 0) ? acquisitionCost(shown) : null;
                const realizedEntry = realizedBySale.get(t.id);
                const original = t.correctsId ? byId.get(t.correctsId) : undefined;
                return (
                  <div key={t.id} className="flex items-center gap-3 px-4 py-3.5">
                    <div className="relative shrink-0">
                      <ProductImage product={product} size="xs" className="size-11 rounded-xl" />
                      <span className="absolute -bottom-1 -right-1 flex size-5 items-center justify-center rounded-full border-2 border-surface bg-surface-3">
                        <Icon className={cn("size-3", t.type === "sale" ? "text-up" : "text-muted")} />
                      </span>
                    </div>
                    <div className="min-w-0 flex-1">
                      <Link href={`/product/${encodeURIComponent(t.productId)}`} className="block truncate text-[15px] font-medium hover:underline">
                        {product?.name ?? t.productId}
                      </Link>
                      <p className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-[13px] text-muted">
                        <span>{meta.label}</span>
                        {t.type !== "correction" ? (
                          <span className="tabular">
                            · {Math.abs(shown.quantity)} × {money(shown.unitPrice)}
                          </span>
                        ) : (
                          <span>
                            · {t.quantity === 0 ? "deleted" : "edited"} {original ? `${original.type} from ${formatDate(original.date)}` : "entry"}
                          </span>
                        )}
                        <span>· {formatDate(shown.date)}</span>
                        {t.source && <span>· {t.source}</span>}
                        {t.grade && <span>· {t.grade.company} {t.grade.grade}</span>}
                        {voided && <Badge>Deleted</Badge>}
                        {corrected && <Badge>Edited</Badge>}
                      </p>
                      {t.notes && <p className="mt-0.5 truncate text-[13px] text-subtle">{t.notes}</p>}
                    </div>
                    <div className="shrink-0 text-right">
                      {amount !== null && (
                        <p className={cn("tabular text-[15px] font-medium", voided && "text-subtle line-through")}>
                          {t.type === "sale" ? "+" : "−"}
                          {money(amount)}
                        </p>
                      )}
                      {realizedEntry && <Delta value={realizedEntry.gain} className="text-[13px]" />}
                      {t.type === "adjustment" && t.quantity < 0 && realizedEntry && <p className="text-[13px] text-subtle">written off</p>}
                    </div>
                    {t.type !== "correction" && !voided ? <TransactionActions tx={t} /> : <span className="w-8" />}
                  </div>
                );
              })}
            </Card>
          </section>
        ))}
      </div>
    </div>
  );
}
