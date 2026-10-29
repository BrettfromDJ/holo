"use client";

import { AlertTriangle, ArrowDownLeft, ArrowUpRight, Eye, Loader2, Minus, Plus, SlidersHorizontal, Trash2 } from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { DealPicker, type DealItem, type DealSide } from "@/components/deal/deal-picker";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DEFAULT_RATES, dealKind, dealTotals, defaultSideRates, unitPrice, type DealKind, type DealRates, type DealTotals } from "@/lib/deal";
import { fifoCost } from "@/lib/finance/sell";
import { money, pct, signedMoney } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useSyncedState } from "@/lib/store/synced-state";
import type { Condition } from "@/lib/types";
import { cn } from "@/lib/utils";

interface DealState {
  in: DealItem[];
  out: DealItem[];
  /** Rates moved off the defaults for this deal; null follows the presets. */
  rateIn: number | null;
  rateOut: number | null;
}

interface DealRecord {
  id: string;
  at: string;
  kind: DealKind;
  inValue: number;
  outValue: number;
  balance: number;
  profit: number | null;
  equity: number;
  items: number;
}

const EMPTY: DealState = { in: [], out: [], rateIn: null, rateOut: null };
const KIND_LABEL: Record<DealKind, string> = { buy: "Buying", sell: "Selling", trade: "Trade", empty: "New deal" };

/**
 * Deal maker for card shows: what comes in and what goes out, each valued at
 * a share of market, with your cost and profit on everything you hand over and
 * cash to settle the difference. Closing the deal records it all in inventory.
 */
export default function DealPage() {
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const { addTransaction, importProduct, today, data } = useStore();
  const [stored, setDeal] = useSyncedState<DealState>("deal", EMPTY);
  const deal = { ...EMPTY, ...stored };
  const [rates, setRates] = useSyncedState<DealRates>("deal-rates", DEFAULT_RATES);
  const [log, setLog] = useSyncedState<DealRecord[]>("deals", []);
  const [picking, setPicking] = useState<DealSide | null>(null);
  const [ratesOpen, setRatesOpen] = useState(false);
  const [customer, setCustomer] = useState(false);
  const [closing, setClosing] = useState(false);

  const byKey = useMemo(() => new Map(holdings.map((h) => [h.key, h])), [holdings]);
  const kind = dealKind(deal.in.length, deal.out.length);
  const defaults = defaultSideRates(kind, { ...DEFAULT_RATES, ...rates });
  const rate = { in: deal.rateIn ?? defaults.in, out: deal.rateOut ?? defaults.out };

  // Your cost for each outgoing row: oldest units first, like the sale will be recorded.
  const costOf = (item: DealItem) => {
    const h = item.holdingKey ? byKey.get(item.holdingKey) : undefined;
    return h ? Math.round(fifoCost(h.lots, item.qty) * 100) / 100 : null;
  };
  const totals = dealTotals(
    deal.in.map((i) => ({ market: i.market, qty: i.qty, price: i.price })),
    deal.out.map((i) => ({ market: i.market, qty: i.qty, price: i.price, cost: costOf(i) })),
    rate,
  );
  const unpriced = [...deal.in.map((i) => unitPrice(i, rate.in)), ...deal.out.map((i) => unitPrice(i, rate.out))].some((p) => p === null);

  const update = (side: DealSide, items: DealItem[]) => setDeal({ ...deal, [side]: items });
  const add = (side: DealSide, item: DealItem) => {
    const existing = deal[side].find((i) => i.key === item.key);
    if (existing) update(side, deal[side].map((i) => (i.key === item.key ? { ...i, qty: Math.min(i.qty + 1, i.maxQty ?? Infinity) } : i)));
    else update(side, [...deal[side], item]);
  };

  const todays = log.filter((d) => d.at.slice(0, 10) === today);

  const close = async () => {
    if (unpriced || kind === "empty") return;
    setClosing(true);
    const note = `Show deal (${KIND_LABEL[kind].toLowerCase()})`;
    try {
      for (const item of deal.out) {
        const h = item.holdingKey ? byKey.get(item.holdingKey) : undefined;
        if (!h) continue;
        await addTransaction({ ...h.identity, type: "sale", date: today, quantity: item.qty, unitPrice: unitPrice(item, rate.out)!, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: note });
      }
      for (const item of deal.in) {
        const h = item.holdingKey ? byKey.get(item.holdingKey) : undefined;
        // Catalog items need saving before they can be held.
        if (!h && !data.products[item.product.id]) await importProduct(item.product.id, item.printing ?? null, item.product.kind);
        const identity = h?.identity ?? { productId: item.product.id, printing: item.printing ?? null, condition: (item.product.kind === "sealed" ? "Sealed" : "Near Mint") as Condition, grade: null };
        // What you give for it becomes its cost, so later profit is measured from the deal.
        await addTransaction({ ...identity, type: "purchase", date: today, quantity: item.qty, unitPrice: unitPrice(item, rate.in)!, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: note });
      }
      setLog([{ id: crypto.randomUUID(), at: new Date().toISOString(), kind, inValue: totals.inValue, outValue: totals.outValue, balance: totals.balance, profit: totals.profit, equity: totals.equity, items: deal.in.length + deal.out.length }, ...log].slice(0, 500));
      setDeal(EMPTY);
      toast.success(`${KIND_LABEL[kind]} recorded`, { description: totals.profit !== null ? `Profit ${signedMoney(totals.profit)}` : undefined });
    } catch (err) {
      toast.error("Couldn't record the deal", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setClosing(false);
    }
  };

  return (
    <div className="animate-fade-in pb-28 lg:pb-0">
      <PageHeader
        title="Deal"
        subtitle="Buys, sells and trades at the table"
        actions={
          <div className="flex gap-1">
            <Button variant="ghost" size="icon" aria-label="Default rates" onClick={() => setRatesOpen(true)}>
              <SlidersHorizontal />
            </Button>
            <Button variant="ghost" size="icon" aria-label="Customer view" onClick={() => setCustomer(true)} disabled={kind === "empty"}>
              <Eye />
            </Button>
          </div>
        }
      />

      {todays.length > 0 && <TodayStrip deals={todays} />}

      <Balance totals={totals} kind={kind} />

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        <SideCard
          side="in"
          items={deal.in}
          rate={rate.in}
          rateDefault={defaults.in}
          total={totals.inValue}
          onRate={(r) => setDeal({ ...deal, rateIn: r })}
          onChange={(items) => update("in", items)}
          onAdd={() => setPicking("in")}
        />
        <SideCard
          side="out"
          items={deal.out}
          rate={rate.out}
          rateDefault={defaults.out}
          total={totals.outValue}
          costOf={costOf}
          onRate={(r) => setDeal({ ...deal, rateOut: r })}
          onChange={(items) => update("out", items)}
          onAdd={() => setPicking("out")}
        />
      </div>

      {/* Close bar: pinned above the tab bar on phones. */}
      {kind !== "empty" && (
        <div className="fixed inset-x-0 bottom-[calc(4.5rem+env(safe-area-inset-bottom))] z-30 px-4 lg:static lg:mt-6 lg:px-0">
          <div className="mx-auto flex max-w-[640px] gap-2 rounded-2xl border border-border bg-surface/95 p-2 shadow-2xl shadow-black/50 backdrop-blur-xl lg:max-w-none lg:border-0 lg:bg-transparent lg:p-0 lg:shadow-none">
            <Button variant="secondary" size="lg" onClick={() => setDeal(EMPTY)}>
              Clear
            </Button>
            <Button variant="lime" size="lg" className="flex-1" disabled={unpriced || closing} onClick={() => void close()}>
              {closing && <Loader2 className="animate-spin" />}
              {unpriced ? "Price every item to close" : `Close ${KIND_LABEL[kind].toLowerCase()}`}
            </Button>
          </div>
        </div>
      )}

      <DealPicker side={picking} onClose={() => setPicking(null)} onPick={(item) => picking && add(picking, item)} />
      <RatesDialog open={ratesOpen} onOpenChange={setRatesOpen} rates={{ ...DEFAULT_RATES, ...rates }} onSave={setRates} />
      <CustomerView open={customer} onOpenChange={setCustomer} deal={deal} rate={rate} totals={totals} />
    </div>
  );
}

/* ------------------------------- Balance ---------------------------------- */

function Balance({ totals, kind }: { totals: DealTotals; kind: DealKind }) {
  const { balance } = totals;
  const even = Math.abs(balance) < 0.005;
  return (
    <section aria-live="polite" className="tint tint-lime tint-borderless rounded-[var(--radius-card)] p-5 sm:p-6">
      <div className="flex items-center justify-between gap-3">
        <span className="tag-skew tag-white">{KIND_LABEL[kind]}</span>
        {totals.belowCost > 0 && (
          <span className="flex items-center gap-1.5 text-[12px] font-medium text-down">
            <AlertTriangle className="size-3.5" /> {totals.belowCost} below cost
          </span>
        )}
      </div>
      <p className="mt-4 font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{kind === "empty" ? "Add items to start" : even ? "Settled" : balance > 0 ? "Customer pays you" : "You pay the customer"}</p>
      <p className="hype-num tabular mt-1 text-[56px] leading-none sm:text-[68px]">{money(Math.abs(balance))}</p>
      <dl className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Coming in" value={money(totals.inValue)} />
        <Stat label="Going out" value={money(totals.outValue)} />
        <Stat label="Profit on sale" value={totals.profit === null ? "—" : <span className={totals.profit >= 0 ? "text-up" : "text-down"}>{signedMoney(totals.profit)}</span>} />
        <Stat label="Equity taken in" value={kind === "sell" || kind === "empty" ? "—" : <span className={totals.equity >= 0 ? "text-up" : "text-down"}>{signedMoney(totals.equity)}</span>} />
      </dl>
    </section>
  );
}

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">{label}</dt>
      <dd className="tabular mt-1 truncate text-[16px] font-semibold">{value}</dd>
    </div>
  );
}

function TodayStrip({ deals }: { deals: DealRecord[] }) {
  const cash = deals.reduce((s, d) => s + d.balance, 0);
  const profit = deals.reduce((s, d) => s + (d.profit ?? 0), 0);
  return (
    <div className="tabular mb-4 flex flex-wrap items-center gap-x-5 gap-y-1 text-[13px] text-muted">
      <span className="font-mono text-[11px] uppercase tracking-[0.06em] text-subtle">Today</span>
      <span>
        <span className="font-semibold text-foreground">{deals.length}</span> deal{deals.length === 1 ? "" : "s"}
      </span>
      <span>
        Cash <span className={cn("font-semibold", cash >= 0 ? "text-up" : "text-down")}>{signedMoney(cash)}</span>
      </span>
      <span>
        Profit <span className={cn("font-semibold", profit >= 0 ? "text-up" : "text-down")}>{signedMoney(profit)}</span>
      </span>
    </div>
  );
}

/* --------------------------------- Sides ---------------------------------- */

function SideCard({
  side,
  items,
  rate,
  rateDefault,
  total,
  costOf,
  onRate,
  onChange,
  onAdd,
}: {
  side: DealSide;
  items: DealItem[];
  rate: number;
  rateDefault: number;
  total: number;
  costOf?: (item: DealItem) => number | null;
  onRate: (r: number | null) => void;
  onChange: (items: DealItem[]) => void;
  onAdd: () => void;
}) {
  const set = (key: string, patch: Partial<DealItem>) => onChange(items.map((i) => (i.key === key ? { ...i, ...patch } : i)));
  const Icon = side === "in" ? ArrowDownLeft : ArrowUpRight;
  return (
    <section className="min-w-0">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="flex items-center gap-2 font-display text-[22px] uppercase leading-none tracking-[0.01em]">
            <Icon className={cn("size-5", side === "in" ? "text-up" : "text-[var(--plan-pink)]")} />
            {side === "in" ? "Coming in" : "Going out"}
          </h2>
          <p className="mt-1 text-[12px] text-muted">{side === "in" ? "What the customer hands you" : "What you hand over"}</p>
        </div>
        <p className="hype-num tabular text-[26px] leading-none">{money(total)}</p>
      </div>

      {/* Counter-offer slider: drag the rate and watch the totals move. */}
      <div className="mt-4 rounded-2xl bg-surface p-3.5 ring-1 ring-inset ring-border">
        <div className="flex items-baseline justify-between">
          <span className="text-[13px] font-medium">
            At <span className="tabular">{pct(rate, 0)}</span> of market
          </span>
          {Math.abs(rate - rateDefault) > 0.0001 && (
            <button className="text-[12px] text-muted hover:text-foreground" onClick={() => onRate(null)}>
              Reset to {pct(rateDefault, 0)}
            </button>
          )}
        </div>
        <input
          type="range"
          min={40}
          max={120}
          step={1}
          value={Math.round(rate * 100)}
          onChange={(e) => onRate(Number(e.target.value) / 100)}
          aria-label={`${side === "in" ? "Coming in" : "Going out"} rate`}
          className="deal-range mt-2.5 w-full"
        />
      </div>

      <ul className="mt-3 space-y-2">
        {items.map((item) => {
          const cost = costOf?.(item) ?? null;
          const p = unitPrice(item, rate);
          const lineTotal = p === null ? null : p * item.qty;
          const profit = cost !== null && lineTotal !== null ? lineTotal - cost : null;
          return (
            <li key={item.key} className="flex gap-3 rounded-2xl bg-surface p-3 ring-1 ring-inset ring-border">
              <ProductImage product={item.product} size="xs" className="h-16 w-12 shrink-0 rounded-lg" />
              <div className="min-w-0 flex-1">
                <div className="flex items-start justify-between gap-2">
                  <p className="line-clamp-2 text-[14px] font-medium leading-snug">{item.product.name}</p>
                  <button aria-label={`Remove ${item.product.name}`} className="shrink-0 pt-0.5 text-subtle hover:text-foreground" onClick={() => onChange(items.filter((i) => i.key !== item.key))}>
                    <Trash2 className="size-3.5" />
                  </button>
                </div>
                <p className="tabular mt-0.5 text-[12px] text-muted">Market {money(item.market)}</p>
                <div className="mt-2 flex flex-wrap items-center gap-2">
                  <div className="flex items-center rounded-full bg-surface-2">
                    <button aria-label="Fewer" className="flex size-7 items-center justify-center text-muted hover:text-foreground disabled:opacity-30" disabled={item.qty <= 1} onClick={() => set(item.key, { qty: item.qty - 1 })}>
                      <Minus className="size-3" />
                    </button>
                    <span className="tabular w-5 text-center text-[13px]">{item.qty}</span>
                    <button aria-label="More" className="flex size-7 items-center justify-center text-muted hover:text-foreground disabled:opacity-30" disabled={item.maxQty !== undefined && item.qty >= item.maxQty} onClick={() => set(item.key, { qty: item.qty + 1 })}>
                      <Plus className="size-3" />
                    </button>
                  </div>
                  <span className="relative">
                    <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-[13px] text-subtle">$</span>
                    <input
                      inputMode="decimal"
                      aria-label="Price each"
                      value={item.price ?? ""}
                      placeholder={p === null ? "Price" : p.toFixed(2)}
                      onChange={(e) => {
                        const v = e.target.value.replace(/[^0-9.]/g, "");
                        set(item.key, { price: v === "" ? null : Number(v) });
                      }}
                      className={cn("tabular h-7 w-24 rounded-full pl-6 pr-2 text-[13px] outline-none placeholder:text-foreground/70 focus:bg-surface-3", item.price !== null ? "bg-surface-3 ring-1 ring-[var(--lime)]/50" : "bg-surface-2")}
                    />
                  </span>
                  <span className="text-[11px] text-subtle">each</span>
                </div>
                {side === "out" && (
                  <p className="tabular mt-2 text-[12px] text-muted">
                    In it {cost === null ? "—" : money(cost)}
                    {profit !== null && (
                      <>
                        {" · "}
                        <span className={profit >= 0 ? "text-up" : "text-down"}>{signedMoney(profit)}</span>
                        {profit < 0 && <span className="ml-1.5 tag-skew tag-pink !text-[10px]">Below cost</span>}
                      </>
                    )}
                  </p>
                )}
              </div>
            </li>
          );
        })}
      </ul>
      <Button variant="secondary" className="mt-2 w-full" onClick={onAdd}>
        <Plus /> {side === "in" ? "Add what's coming in" : "Add from inventory"}
      </Button>
    </section>
  );
}

/* ------------------------------ Rate presets ------------------------------ */

function RatesDialog({ open, onOpenChange, rates, onSave }: { open: boolean; onOpenChange: (o: boolean) => void; rates: DealRates; onSave: (r: DealRates) => void }) {
  const rows: { key: keyof DealRates; label: string; hint: string }[] = [
    { key: "buy", label: "Buying", hint: "What you pay for items you buy outright" },
    { key: "trade", label: "Trade-in", hint: "What you credit for items taken in on trade" },
    { key: "sell", label: "Selling", hint: "What you charge for items going out" },
  ];
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[440px]">
        <DialogHeader>
          <DialogTitle>Default rates</DialogTitle>
          <DialogDescription>As a share of market. Every new deal starts here; drag a side&apos;s slider to counter.</DialogDescription>
        </DialogHeader>
        <div className="space-y-5 px-6 pb-6 pt-2">
          {rows.map((r) => (
            <div key={r.key}>
              <div className="flex items-baseline justify-between">
                <span className="text-[14px] font-medium">{r.label}</span>
                <span className="hype-num tabular text-[22px]">{pct(rates[r.key], 0)}</span>
              </div>
              <p className="text-[12px] text-muted">{r.hint}</p>
              <input type="range" min={40} max={120} step={1} value={Math.round(rates[r.key] * 100)} onChange={(e) => onSave({ ...rates, [r.key]: Number(e.target.value) / 100 })} aria-label={`${r.label} rate`} className="deal-range mt-2 w-full" />
            </div>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}

/* ----------------------------- Customer view ------------------------------ */

/** What the customer sees: items and prices, no market, costs or margins. */
function CustomerView({ open, onOpenChange, deal, rate, totals }: { open: boolean; onOpenChange: (o: boolean) => void; deal: DealState; rate: { in: number; out: number }; totals: DealTotals }) {
  const list = (items: DealItem[], r: number) =>
    items.map((i) => (
      <li key={i.key} className="flex items-center gap-3 py-2">
        <ProductImage product={i.product} size="xs" className="h-14 w-10 shrink-0 rounded-md" />
        <span className="min-w-0 flex-1 text-[15px] font-medium">
          {i.product.name}
          {i.qty > 1 && <span className="text-muted"> × {i.qty}</span>}
        </span>
        <span className="tabular shrink-0 text-[16px] font-semibold">{money((unitPrice(i, r) ?? 0) * i.qty)}</span>
      </li>
    ));
  const even = Math.abs(totals.balance) < 0.005;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[560px]">
        <DialogHeader>
          <DialogTitle>Your deal</DialogTitle>
          <DialogDescription>Turn the screen around to show the customer.</DialogDescription>
        </DialogHeader>
        <div className="flex-1 overflow-y-auto px-6 pb-6">
          {deal.in.length > 0 && (
            <>
              <p className="mt-2 font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">You&apos;re bringing</p>
              <ul className="divide-y divide-border">{list(deal.in, rate.in)}</ul>
            </>
          )}
          {deal.out.length > 0 && (
            <>
              <p className="mt-5 font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">You&apos;re taking home</p>
              <ul className="divide-y divide-border">{list(deal.out, rate.out)}</ul>
            </>
          )}
          <div className="mt-6 rounded-2xl bg-surface-2 p-5 text-center">
            <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{even ? "Straight swap" : totals.balance > 0 ? "You pay" : "We pay you"}</p>
            <p className="hype-num tabular mt-1 text-[56px] leading-none">{money(Math.abs(totals.balance))}</p>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
