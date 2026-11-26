"use client";

import { FileText, Info, Share } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { Chips, GlassStat, Heading, RowMore, SearchBox, toneOf } from "@/components/analytics/bits";
import { EntryActions } from "@/components/sales/entry-actions";
import { EmptyPage } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { effectiveTransactions } from "@/lib/finance/ledger";
import { daysHeld, saleFees, salesCsv, salesLines, salesTotals, salesYears, type SaleLine } from "@/lib/finance/sales-report";
import { formatShortDate, money, signedMoney } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import type { Transaction } from "@/lib/types";
import { cn } from "@/lib/utils";

const FIRST_PAGE = 50;
const count = (q: number) => (Number.isInteger(q) ? String(q) : String(+q.toFixed(3)));

function held(days: number): string {
  if (days < 60) return `${days} ${days === 1 ? "day" : "days"}`;
  const months = Math.round(days / 30.44);
  if (months < 24) return `${months} mo`;
  return `${(days / 365.25).toFixed(1)} yr`;
}

/**
 * Sales & taxes, like the app's `SalesView`: what you sold in a year, what those copies cost and
 * the profit, split by how long you held them, with a spreadsheet for an accountant. Covers every
 * portfolio. Built for vendors with hundreds of sales: the report is worked out once per log
 * change, sales are grouped by month, a search shows past 8 sales, and the list starts at 50.
 */
export function SalesView() {
  const store = useStore();
  const transactions = store.data.transactions;
  const all = useMemo(() => salesLines(transactions), [transactions]);
  const fees = useMemo(() => saleFees(transactions), [transactions]);
  const years = useMemo(() => salesYears(all), [all]);
  const [year, setYear] = useState<number | null>(null);
  const [query, setQuery] = useState("");
  const [showAll, setShowAll] = useState(false);
  const [info, setInfo] = useState(false);
  const [acting, setActing] = useState<Transaction | null>(null);

  const shown = year ?? years[0] ?? new Date().getFullYear();
  const lines = useMemo(() => (shown === 0 ? all : all.filter((l) => l.year === shown)), [all, shown]);
  const t = useMemo(() => salesTotals(lines), [lines]);
  const feeTotal = useMemo(() => [...new Set(lines.map((l) => l.saleId))].reduce((s, id) => s + (fees.get(id) ?? 0), 0), [lines, fees]);
  const gains = lines.reduce((s, l) => s + Math.max(0, l.gain), 0);
  const losses = lines.reduce((s, l) => s + Math.min(0, l.gain), 0);

  const q = query.trim().toLowerCase();
  const found = useMemo(() => (q ? lines.filter((l) => (store.data.products[l.identity.productId]?.name ?? "").toLowerCase().includes(q)) : lines), [lines, q, store.data.products]);
  const visible = showAll || q ? found : found.slice(0, FIRST_PAGE);
  const months = useMemo(() => byMonth(visible), [visible]);

  if (store.status === "loading") return <Skeleton className="h-[600px] w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  const exportCsv = () => {
    const csv = salesCsv(lines, store.data.products);
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `${shown === 0 ? "Corodex sales" : `Corodex sales ${shown}`}.csv`;
    a.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const openActions = (l: SaleLine) => {
    const tx = effectiveTransactions(transactions).find((x) => x.id === l.saleId);
    if (tx) setActing(tx);
  };

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Sales & taxes"
        className="mb-6"
        actions={
          all.length > 0 ? (
            <button type="button" onClick={exportCsv} aria-label="Export for your accountant" title="Export for your accountant" className="glass flex size-10 items-center justify-center rounded-full transition-opacity hover:opacity-80">
              <Share className="size-[18px]" />
            </button>
          ) : undefined
        }
      />

      {all.length === 0 ? (
        <EmptyPage title="No sales yet" line="When you sell something, mark it sold on its page. Your profit for the year shows up here, ready for tax time." icon={FileText} />
      ) : (
        <div className="flex max-w-[760px] flex-col gap-8">
          <Chips
            label="Year"
            scrolls
            value={shown}
            onChange={(v) => {
              setYear(v);
              setShowAll(false);
            }}
            options={[{ value: 0, label: "All" }, ...years.map((y) => ({ value: y, label: String(y) }))]}
          />

          <section className="space-y-4">
            <div>
              <p className="flex items-center gap-1.5 font-mono text-[11px] uppercase tracking-[0.1em] text-muted">
                {shown === 0 ? "Profit, every year" : `Profit in ${shown}`}
                <button type="button" onClick={() => setInfo(true)} aria-label="About these numbers" className="text-subtle hover:text-muted">
                  <Info className="size-3.5" />
                </button>
              </p>
              <p className={cn("tabular mt-1.5 font-display text-[48px] leading-none", t.gain >= 0 ? "text-up" : "text-down")}>{signedMoney(t.gain)}</p>
              <p className="mt-2 text-[14px] text-muted">
                From {t.sales} {t.sales === 1 ? "sale" : "sales"} · {count(t.quantity)} {t.quantity === 1 ? "copy" : "copies"}
              </p>
            </div>
            <div className="flex gap-2">
              <GlassStat label="Gains" value={signedMoney(gains)} tone={gains > 0 ? "up" : "quiet"} />
              <GlassStat label="Losses" value={losses < 0 ? signedMoney(losses) : "—"} tone={losses < 0 ? "down" : "quiet"} />
            </div>
            <div className="flex gap-2">
              <GlassStat label="Sold for" value={money(t.proceeds)} />
              <GlassStat label="They cost" value={money(t.cost)} />
              <GlassStat label="Fees" value={feeTotal > 0 ? money(feeTotal) : "—"} tone={feeTotal > 0 ? undefined : "quiet"} />
            </div>
          </section>

          <section className="space-y-3">
            <Heading title="How long you held them" />
            <div className="flex gap-2">
              {[
                { label: "Over a year", gain: t.longTermGain },
                { label: "A year or less", gain: t.shortTermGain },
              ].map((s) => (
                <GlassStat key={s.label} label={s.label} value={Math.abs(s.gain) < 0.005 ? "—" : signedMoney(s.gain)} tone={Math.abs(s.gain) < 0.005 ? "quiet" : toneOf(s.gain)} />
              ))}
            </div>
          </section>

          <section className="space-y-3">
            <Heading title="Every sale" />
            {lines.length > 8 && <SearchBox value={query} onChange={setQuery} placeholder="Find a sale" />}
            {found.length === 0 && <p className="py-3 text-[14px] text-muted">No sales match.</p>}
            <div className="space-y-[18px]">
              {months.map((m) => (
                <div key={m.key} className="space-y-2">
                  <div className="flex items-baseline gap-1.5 px-1">
                    <span className="text-[14px] font-semibold">{longMonth(m.key)}</span>
                    <span className="text-[13px] text-muted">
                      · {m.lines.length} {m.lines.length === 1 ? "sale" : "sales"}
                    </span>
                    <span className={cn("tabular ml-auto text-[13px] font-semibold", m.gain >= 0 ? "text-up" : "text-down")}>{signedMoney(m.gain)}</span>
                  </div>
                  <ul className="divide-y divide-[rgb(255_255_255/0.06)] rounded-2xl border border-border bg-surface px-3.5">
                    {m.lines.map((l) => {
                      const product = store.data.products[l.identity.productId];
                      const days = l.acquired ? daysHeld(l.acquired, l.sold) : null;
                      const detail = [`Sold ${formatShortDate(l.sold)}`, days !== null ? `held ${held(days)}` : null, l.quantity !== 1 ? `×${count(l.quantity)}` : null].filter(Boolean).join(" · ");
                      return (
                        <li key={l.id} className="flex items-center gap-0.5">
                          <Link href={`/product/${encodeURIComponent(l.identity.productId)}`} className="flex min-w-0 flex-1 items-center gap-3 py-2.5">
                            <ProductImage product={product} size="xs" grade={l.identity.grade} className="h-14 w-10 shrink-0 rounded" />
                            <div className="min-w-0 flex-1">
                              <p className="truncate text-[14px] font-semibold">{product?.name ?? "Unknown item"}</p>
                              <p className="truncate text-[12px] text-muted">{detail}</p>
                            </div>
                            <div className="shrink-0 text-right">
                              <p className={cn("tabular text-[14px] font-semibold", l.gain >= 0 ? "text-up" : "text-down")}>{signedMoney(l.gain)}</p>
                              <p className="tabular text-[12px] text-muted">sold for {money(l.proceeds)}</p>
                            </div>
                          </Link>
                          <RowMore onClick={() => openActions(l)} label={`Actions for ${product?.name ?? "this sale"}`} />
                        </li>
                      );
                    })}
                  </ul>
                </div>
              ))}
            </div>
            {!showAll && !q && found.length > FIRST_PAGE && (
              <button type="button" onClick={() => setShowAll(true)} className="glass h-12 w-full rounded-full text-[15px] font-semibold transition-opacity hover:opacity-85">
                Show all {found.length} sales
              </button>
            )}
          </section>
        </div>
      )}

      <Dialog open={info} onOpenChange={setInfo}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader className="pb-6">
            <DialogTitle className="font-display">About these numbers</DialogTitle>
            <DialogDescription asChild>
              <div className="space-y-3 text-[14px]">
                <p>Profit is what each sale brought in after its fees, shipping and tax, minus what those copies cost you, oldest copies first. Cards you pulled count as costing nothing.</p>
                <p>In the US, collectibles held over a year are taxed at up to 28%. A year or less is taxed like income. Your accountant will know what applies to you.</p>
                <p>A guide for your records, not tax advice.</p>
              </div>
            </DialogDescription>
          </DialogHeader>
        </DialogContent>
      </Dialog>

      <EntryActions
        tx={acting}
        title={acting ? (store.data.products[acting.productId]?.name ?? "Sale") : "Sale"}
        noun="sale"
        deleteNote="The copies go back into your collection. The original stays in the record."
        onClose={() => setActing(null)}
      />
    </div>
  );
}

interface Month {
  key: string;
  lines: SaleLine[];
  gain: number;
}

/** The sales in month groups, newest month first (they arrive newest first). */
function byMonth(lines: SaleLine[]): Month[] {
  const groups = new Map<string, SaleLine[]>();
  for (const l of lines) {
    const key = l.sold.slice(0, 7);
    const list = groups.get(key);
    if (list) list.push(l);
    else groups.set(key, [l]);
  }
  return [...groups.entries()].map(([key, ls]) => ({ key, lines: ls, gain: ls.reduce((s, l) => s + l.gain, 0) }));
}

/** "October 2026" for a yyyy-MM key. */
function longMonth(key: string): string {
  const d = new Date(`${key}-01T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? key : d.toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
}
