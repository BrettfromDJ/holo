"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Chips, GlassStat, RowMore, SearchBox, toneOf } from "@/components/analytics/bits";
import { partitionHistory } from "@/components/flows/transaction-dialogs";
import { EntryActions } from "@/components/sales/entry-actions";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { ProductImage } from "@/components/product/product-image";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { PageHeader } from "@/components/shell/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { acquisitionCost, saleProceeds } from "@/lib/finance/ledger";
import { formatShortDate, money, signedMoney } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { holdingKey, type Transaction } from "@/lib/types";
import { cn } from "@/lib/utils";

type Filter = "all" | "purchase" | "sale" | "pulls" | "adjustment";
const PULLED = "Pulled";
const isPull = (t: Transaction) => t.type === "purchase" && t.source === PULLED;
const QUIET_NOTES = new Set(["Deleted", "Edited", "Voided", "Corrected"]);

/**
 * Every purchase, sale and adjustment, newest first and grouped by month, like the app's
 * `ActivityView`. Follows the portfolio picker. Deleted entries and the records that edited or
 * deleted them stay hidden unless you ask to see them; edit or delete any live entry from its ⋯.
 */
export default function ActivityPage() {
  const store = useStore();
  const { realized } = usePortfolio();
  const [filter, setFilter] = useState<Filter>("all");
  const [showHidden, setShowHidden] = useState(false);
  const [query, setQuery] = useState("");
  const [acting, setActing] = useState<Transaction | null>(null);

  // The ledger work, once per change to the log (not per filter or keystroke).
  const base = useMemo(() => {
    const keep = store.holdingFilter;
    const all = keep ? store.data.transactions.filter((t) => keep(holdingKey(t))) : store.data.transactions;
    const { effective, visible, hidden } = partitionHistory(all);
    let bought = 0;
    let sold = 0;
    for (const t of effective.values()) {
      if (t.type === "purchase" || (t.type === "adjustment" && t.quantity > 0)) bought += acquisitionCost(t);
      if (t.type === "sale") sold += saleProceeds(t);
    }
    return { all, visible, effective, byId: new Map(all.map((t) => [t.id, t])), hiddenCount: hidden.length, bought, sold };
  }, [store.data.transactions, store.holdingFilter]);

  const months = useMemo(() => {
    const q = query.trim().toLowerCase();
    const products = store.data.products;
    const list = (showHidden ? base.all : base.visible)
      .filter((t) => {
        const edits = showHidden && t.type === "correction";
        switch (filter) {
          case "all":
            return true;
          case "purchase":
            return (t.type === "purchase" && !isPull(t)) || edits;
          case "pulls":
            return isPull(t);
          case "sale":
            return t.type === "sale" || edits;
          case "adjustment":
            return t.type === "adjustment" || edits;
        }
      })
      .filter((t) => {
        if (!q) return true;
        const p = products[t.productId];
        return (p?.name ?? t.productId).toLowerCase().includes(q) || (p?.setName ?? "").toLowerCase().includes(q);
      })
      .sort((a, b) => (a.date === b.date ? (a.createdAt < b.createdAt ? 1 : -1) : a.date < b.date ? 1 : -1));
    const groups = new Map<string, Transaction[]>();
    for (const t of list) {
      const key = t.date.slice(0, 7);
      const g = groups.get(key);
      if (g) g.push(t);
      else groups.set(key, [t]);
    }
    return [...groups.entries()];
  }, [base, filter, showHidden, query, store.data.products]);

  const realizedBySale = useMemo(() => new Map(realized.map((r) => [r.transactionId, r])), [realized]);
  const realizedTotal = useMemo(() => realized.reduce((sum, r) => sum + r.gain, 0), [realized]);

  if (store.status === "loading") return <Skeleton className="h-96 w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) {
    return (
      <>
        <PageHeader title="Activity" />
        <EmptyCollection title="No activity yet" body="Add a purchase and it shows up here." />
      </>
    );
  }

  const count = base.effective.size;

  /** Each month's money, on its heading: "spent $124 · sold $879". */
  const monthTotals = (rows: Transaction[]) => {
    let spent = 0;
    let sold = 0;
    for (const t of rows) {
      const e = base.effective.get(t.id);
      if (!e) continue;
      if (e.type === "purchase" || (e.type === "adjustment" && e.quantity > 0)) spent += acquisitionCost(e);
      if (e.type === "sale") sold += saleProceeds(e);
    }
    return [spent > 0 ? `spent ${money(spent)}` : null, sold > 0 ? `sold ${money(sold)}` : null].filter(Boolean).join(" · ");
  };

  return (
    <div className="animate-fade-in">
      <header className="relative isolate mb-6">
        <div aria-hidden className="page-dots pointer-events-none absolute -inset-x-4 -bottom-8 -top-10 -z-10 sm:-inset-x-8 sm:-top-14" />
        <h1 className="font-display text-[40px] leading-none">Activity</h1>
        <p className="tabular mt-2 text-[15px] text-muted">{count === 1 ? "1 purchase or sale" : `${count} purchases and sales`}</p>
        <div className="mt-5 flex max-w-[560px] gap-2">
          <GlassStat label="Bought" value={money(base.bought)} />
          <GlassStat label="Sold" value={money(base.sold)} />
          <GlassStat label="Realized" value={signedMoney(realizedTotal)} tone={toneOf(realizedTotal)} href="/sales" />
        </div>
      </header>
      <PortfolioSwitcher compact className="mb-3 lg:hidden" />
      <PortfolioBanner />

      <div className="flex max-w-[760px] flex-col gap-4">
        <SearchBox value={query} onChange={setQuery} placeholder="Find a card" />
        <Chips
          label="Filter activity"
          scrolls
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "All" },
            { value: "purchase", label: "Bought" },
            { value: "sale", label: "Sold" },
            { value: "pulls", label: "Pulls" },
            { value: "adjustment", label: "Other" },
          ]}
        />
        {base.hiddenCount > 0 && (
          <button type="button" onClick={() => setShowHidden((v) => !v)} className="self-start text-[12px] font-medium text-subtle hover:text-muted">
            {showHidden ? "Hide" : "Show"} deleted &amp; edit records ({base.hiddenCount})
          </button>
        )}

        {months.length === 0 && <p className="py-10 text-center text-[15px] text-muted">Nothing matches.</p>}

        <div className="mt-2 space-y-[26px]">
          {months.map(([month, rows]) => (
            <section key={month} className="space-y-2.5">
              <div className="flex items-baseline justify-between gap-3">
                <h2 className="font-display text-[20px] leading-none">{longMonth(month)}</h2>
                <span className="tabular truncate text-[12px] text-muted">{monthTotals(rows)}</span>
              </div>
              <ul className="overflow-hidden rounded-2xl border border-border bg-surface">
                {rows.map((t, i) => (
                  <Row key={t.id} t={t} first={i === 0} base={base} gain={realizedBySale.get(t.id)?.gain ?? null} onActions={() => setActing(base.effective.get(t.id) ?? t)} />
                ))}
              </ul>
            </section>
          ))}
        </div>
      </div>

      <EntryActions
        tx={acting}
        title={acting ? (store.data.products[acting.productId]?.name ?? "Entry") : "Entry"}
        deleteNote="Your totals update as if it never happened. The original stays in the record."
        onClose={() => setActing(null)}
      />
    </div>
  );
}

function Row({
  t,
  first,
  base,
  gain,
  onActions,
}: {
  t: Transaction;
  first: boolean;
  base: { effective: Map<string, Transaction>; byId: Map<string, Transaction> };
  gain: number | null;
  onActions: () => void;
}) {
  const { data } = useStore();
  const product = data.products[t.productId];
  const eff = base.effective.get(t.id);
  const voided = t.type !== "correction" && !eff;
  const shown = eff ?? t;
  const edited = !!eff && (eff.unitPrice !== t.unitPrice || eff.quantity !== t.quantity || eff.date !== t.date || eff.fees !== t.fees);
  const amount = t.type === "sale" ? saleProceeds(shown) : t.type === "purchase" || (t.type === "adjustment" && t.quantity > 0) ? acquisitionCost(shown) : null;
  const original = t.correctsId ? base.byId.get(t.correctsId) : undefined;
  const what = t.type === "correction" ? `${t.quantity === 0 ? "deleted" : "edited"} ${original ? `${original.type} from ${formatShortDate(original.date)}` : "entry"}` : `${Math.abs(shown.quantity)} × ${money(shown.unitPrice)}`;
  const grade = t.grade ? `${t.grade.company} ${t.grade.grade}` : null;
  const meta = [what, isPull(t) ? null : t.source, grade, t.type === "correction" ? null : formatShortDate(shown.date)].filter(Boolean).join(" · ");
  const editable = t.type !== "correction" && !voided;
  const plainBuy = t.type === "purchase" && !isPull(t);
  const tag: [string, string] =
    t.type === "sale" ? ["Sold", "text-lime"] : isPull(t) ? ["Pulled", "text-[var(--plan-blue)]"] : t.type === "adjustment" ? [t.quantity > 0 ? "Added" : "Removed", "text-muted"] : t.type === "correction" ? ["Edit record", "text-muted"] : ["Bought", "text-muted"];

  return (
    <li className={cn("flex items-center gap-1 pl-3.5 pr-1.5", !first && "border-t border-border")}>
      <Link href={`/product/${encodeURIComponent(t.productId)}`} className="flex min-w-0 flex-1 items-center gap-3 py-3">
        <ProductImage product={product} size="xs" grade={t.grade} className="h-[52px] w-[38px] shrink-0 rounded" />
        <div className="min-w-0 flex-1 space-y-1">
          <p className="line-clamp-2 text-[14px] font-medium">{product?.name ?? t.productId}</p>
          {(!plainBuy || voided || edited) && (
            <div className="flex gap-1.5">
              {!plainBuy && <Tag className={tag[1]}>{tag[0]}</Tag>}
              {voided && <Tag className="text-muted">Deleted</Tag>}
              {edited && <Tag className="text-muted">Edited</Tag>}
            </div>
          )}
          <p className="tabular truncate text-[12px] text-muted">{meta}</p>
          {t.notes && !QUIET_NOTES.has(t.notes) && <p className="truncate text-[12px] text-subtle">{t.notes}</p>}
        </div>
        <div className="shrink-0 space-y-0.5 text-right">
          {amount !== null && (
            <p className={cn("tabular text-[14px] font-semibold", voided && "text-subtle line-through")}>
              {t.type === "sale" ? "+" : "−"}
              {money(amount)}
            </p>
          )}
          {gain !== null && (
            <p className="tabular text-[12px]">
              <span className="text-subtle">{t.type === "adjustment" ? "written off " : "profit "}</span>
              <span className={gain >= 0 ? "text-up" : "text-down"}>{signedMoney(gain)}</span>
            </p>
          )}
        </div>
      </Link>
      {editable ? <RowMore onClick={onActions} label={`Actions for ${product?.name ?? "this entry"}`} /> : <span className="w-9 shrink-0" />}
    </li>
  );
}

function Tag({ className, children }: { className?: string; children: React.ReactNode }) {
  return <span className={cn("rounded-md bg-foreground/[0.08] px-1.5 py-0.5 font-mono text-[10px] font-medium uppercase tracking-[0.08em]", className)}>{children}</span>;
}

/** "October 2026" for a yyyy-MM key. */
function longMonth(key: string): string {
  const d = new Date(`${key}-01T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? key : d.toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
}
