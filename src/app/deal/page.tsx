"use client";

import { AlertTriangle, ArrowDownLeft, ArrowUpDown, ArrowDownRight, ArrowUpRight, Bookmark, Camera, Check, ChevronDown, Eye, History, Info, Loader2, Minus, ScanLine, Plus, Search, SlidersHorizontal, StickyNote, Trash2 } from "lucide-react";
import { useCallback, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { DealPhotos, deleteDealPhoto } from "@/components/deal/deal-photos";
import { DealPicker, type DealItem, type DealSide } from "@/components/deal/deal-picker";
import { ScanSheet, type ScanOutcome, type ScanPick } from "@/components/scan/scan-sheet";
import { scanValue } from "@/lib/scan-types";
import { EbaySales } from "@/components/product/ebay-sales";
import { SellSpeedTag } from "@/components/product/sell-speed";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Switch } from "@/components/ui/switch";
import { Hint } from "@/components/ui/tooltip";
import { DEFAULT_RATES, aheadTitle, dealDayTotals, dealKind, dealNet, dealTotals, dealVerdict, defaultSideRates, lineRate, matchesDealSearch, parkedDealName, recordAhead, roundedCash, showsEquity, unitPrice, type DealDayTotals, type DealKind, type DealRates, type DealTotals } from "@/lib/deal";
import { fifoCost } from "@/lib/finance/sell";
import { money, pct, signedMoney } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useSyncedState } from "@/lib/store/synced-state";
import type { Condition, Grade, Product } from "@/lib/types";
import { cn } from "@/lib/utils";

interface DealState {
  in: DealItem[];
  out: DealItem[];
  /** Rates moved off the defaults for this deal; null follows the presets. */
  rateIn: number | null;
  rateOut: number | null;
  /** Photos documenting the deal (storage paths, shared with the app). */
  photos?: string[];
  /** Your own notes on the deal (kept with it when it closes). */
  notes?: string;
}

/** A deal set aside to finish later (user_state "deals-parked", shared with the app). */
interface ParkedDeal {
  id: string;
  name: string;
  savedAt: string;
  state: DealState;
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
  /** How far ahead the deal left you (profit + value gained); null when not every item had a cost. Missing on older deals. */
  ahead?: number | null;
  /** Items that went out with no known cost. Recorded alongside `ahead`. */
  uncosted?: number;
  items: number;
  /** What changed hands, for the history. Missing on deals closed before it was kept. */
  lines?: DealRecordLine[];
  photos?: string[];
  notes?: string;
}

interface DealRecordLine {
  side: DealSide;
  product: Pick<Product, "id" | "name" | "imageUrl" | "kind" | "setName" | "productType">;
  qty: number;
  /** Price per unit it went at. */
  price: number;
  /** Not recorded in the collection (left out on purpose, not in Holo, or custom). */
  untracked?: boolean;
}

const EMPTY: DealState = { in: [], out: [], rateIn: null, rateOut: null };
const KIND_LABEL: Record<DealKind, string> = { buy: "Buying", sell: "Selling", trade: "Trade", empty: "New deal" };
/** The deal as a noun: "Close buy", "Sale recorded". */
const KIND_NOUN: Record<DealKind, string> = { buy: "Buy", sell: "Sale", trade: "Trade", empty: "Deal" };

/** What each number means, one sentence each (hover or tap the ⓘ). */
const TERMS = {
  verdict: "Your profit on what you hand over plus the value you gain on what comes in: how much better off you are after this deal, at market prices.",
  ahead: "Market value of what comes in, minus what you paid for what goes out, minus any cash you pay (plus any you get): your profit plus the value you gain.",
  cash: "The difference between the two sides, paid in cash so the deal comes out even.",
  comingIn: "What the customer's cards count for in this deal, at the prices you set.",
  goingOut: "What your cards count for in this deal, at the prices you set.",
  profit: "What your cards go for in this deal, minus what you paid for them.",
  value: "Market value of what comes in, minus what you're giving for it: how far below market you're getting it.",
  rate: "Each item counts for this share of its market price. Drag to counter-offer, or set one item's own % or price.",
};

/**
 * Deal maker for card shows, the same as the app: what comes in and what goes out, each valued
 * at a share of market, with a plain-English verdict, your profit and the value you take in,
 * cash to settle (rounded to $5 in one click), photos, and items that aren't in Holo or aren't
 * in the catalog at all. Closing shows what will happen first, then records it.
 */
export default function DealPage() {
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const { addTransaction, importProduct, today, data } = useStore();
  const [stored, setDeal] = useSyncedState<DealState>("deal", EMPTY);
  const deal = { ...EMPTY, ...stored };
  const photos = deal.photos ?? [];
  const [ratesStored, setRates] = useSyncedState<DealRates>("deal-rates", DEFAULT_RATES);
  const rates = { ...DEFAULT_RATES, ...ratesStored };
  const [log, setLog] = useSyncedState<DealRecord[]>("deals", []);
  // Deals set aside to finish later. Edits are functional so ones made before the account's list
  // loads are replayed on top of it (a failed load never saves over it).
  const [parkedStored, setParked] = useSyncedState<ParkedDeal[]>("deals-parked", []);
  const parked = parkedStored ?? [];
  const [parking, setParking] = useState(false);
  const [parkedOpen, setParkedOpen] = useState(false);
  const [picking, setPicking] = useState<DealSide | null>(null);
  const [ratesOpen, setRatesOpen] = useState(false);
  const [customer, setCustomer] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [closing, setClosing] = useState(false);
  const [recorded, setRecorded] = useState<{ record: DealRecord; totals: DealTotals; deal: DealState } | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [scanning, setScanning] = useState<DealSide | null>(null);
  const [ebayItem, setEbayItem] = useState<DealItem | null>(null);

  const byKey = useMemo(() => new Map(holdings.map((h) => [h.key, h])), [holdings]);
  const kind = dealKind(deal.in.length, deal.out.length);
  const defaults = defaultSideRates(kind, rates);
  const rate = { in: deal.rateIn ?? defaults.in, out: deal.rateOut ?? defaults.out };

  /** Your cost for an outgoing row: oldest units first from inventory, else what you said you paid. */
  const costOf = (item: DealItem) => {
    const h = item.holdingKey ? byKey.get(item.holdingKey) : undefined;
    if (h) return Math.round(fifoCost(h.lots, item.qty) * 100) / 100;
    return item.cost !== null && item.cost !== undefined ? Math.round(item.cost * item.qty * 100) / 100 : null;
  };
  /** Whether closing records this line in your collection. */
  const tracked = (item: DealItem, side: DealSide) => {
    if (item.custom) return false;
    if (side === "in") return item.track ?? rates.addIncoming ?? true;
    return Boolean(item.holdingKey) || (item.cost !== null && item.cost !== undefined);
  };
  const totals = dealTotals(
    deal.in.map((i) => ({ market: i.market, qty: i.qty, price: i.price, rate: i.rate })),
    deal.out.map((i) => ({ market: i.market, qty: i.qty, price: i.price, rate: i.rate, cost: costOf(i) })),
    rate,
  );
  const unpriced = [...deal.in.map((i) => unitPrice(i, rate.in)), ...deal.out.map((i) => unitPrice(i, rate.out))].some((p) => p === null);
  const net = dealNet(totals);
  const summary = `${cashLine(totals.balance)}${totals.ahead !== null ? ` · ${totals.ahead < 0 ? "behind" : "ahead"} ${signedMoney(totals.ahead)}` : net !== null ? ` · you're ${signedMoney(net)}` : ""}`;

  // Updates build on the latest deal, so rapid scans landing back to back all count.
  const update = (side: DealSide, items: DealItem[]) => setDeal((cur) => ({ ...EMPTY, ...cur, [side]: items }));
  const add = (side: DealSide, item: DealItem) =>
    setDeal((cur) => {
      const d = { ...EMPTY, ...cur };
      const existing = d[side].find((i) => i.key === item.key);
      const items = existing ? d[side].map((i) => (i.key === item.key ? { ...i, qty: Math.min(i.qty + 1, i.maxQty ?? Infinity) } : i)) : [...d[side], item];
      return { ...d, [side]: items };
    });
  const setPhotos = (next: string[]) => setDeal((cur) => ({ ...EMPTY, ...cur, photos: next }));

  /** A scanned card: anything can come in; going out, one you don't hold is added as not in Holo. */
  const addScan = (side: DealSide, pick: ScanPick): ScanOutcome => {
    const c = pick.candidate;
    const grade = pick.read?.grade ?? null;
    if (side === "in") {
      const h = holdings.find((x) => x.identity.productId === c.product.id && x.identity.printing === c.printing && sameGrade(x.identity.grade, grade));
      add("in", h ? { key: `h:${h.key}`, product: h.product!, printing: h.identity.printing, market: h.price ?? c.market, qty: 1, price: null, holdingKey: h.key } : { key: `p:${c.product.id}:${c.printing ?? ""}:${gradeLabel(grade)}`, product: c.product, printing: c.printing, market: scanValue(c, pick.read), qty: 1, price: null, grade });
      return { ok: true, note: "Added to coming in" };
    }
    const owned = holdings.filter((x) => x.identity.productId === c.product.id);
    const h = owned.find((x) => x.identity.printing === c.printing && sameGrade(x.identity.grade, grade)) ?? owned[0];
    if (!h) {
      add("out", { key: `p:${c.product.id}:${c.printing ?? ""}:${gradeLabel(grade)}`, product: c.product, printing: c.printing, market: scanValue(c, pick.read), qty: 1, price: null, grade });
      return { ok: true, note: "Added · not in Holo" };
    }
    add("out", { key: `h:${h.key}`, product: h.product!, printing: h.identity.printing, market: h.price, qty: 1, price: null, holdingKey: h.key, maxQty: h.quantity });
    return { ok: true, note: "Added to going out" };
  };

  /** Round the cash to $5 by nudging the price of the biggest item (going out if any, else coming in). */
  const roundTo = kind === "empty" ? null : roundedCash(totals.balance);
  const roundCash = () => {
    if (roundTo === null) return;
    const delta = roundTo - totals.balance;
    setDeal((cur) => {
      const d = { ...EMPTY, ...cur };
      const biggest = (items: DealItem[], r: number) => items.reduce<number>((best, it, i) => ((unitPrice(it, r) ?? 0) * it.qty > (best < 0 ? -1 : (unitPrice(items[best], r) ?? 0) * items[best].qty) ? i : best), -1);
      if (d.out.length) {
        const i = biggest(d.out, rate.out);
        const it = d.out[i];
        const total = (unitPrice(it, rate.out) ?? 0) * it.qty + delta;
        if (total <= 0) return d;
        return { ...d, out: d.out.map((x, j) => (j === i ? { ...x, price: Math.round((total / x.qty) * 100) / 100, rate: null } : x)) };
      }
      const i = biggest(d.in, rate.in);
      const it = d.in[i];
      const total = (unitPrice(it, rate.in) ?? 0) * it.qty - delta;
      if (total <= 0) return d;
      return { ...d, in: d.in.map((x, j) => (j === i ? { ...x, price: Math.round((total / x.qty) * 100) / 100, rate: null } : x)) };
    });
  };

  const todays = log.filter((d) => d.at.slice(0, 10) === today);
  const effects = {
    adds: deal.in.filter((i) => tracked(i, "in")).reduce((s, i) => s + i.qty, 0),
    sells: deal.out.filter((i) => tracked(i, "out")).reduce((s, i) => s + i.qty, 0),
    untracked: [...deal.in.filter((i) => !tracked(i, "in")), ...deal.out.filter((i) => !tracked(i, "out"))].reduce((s, i) => s + i.qty, 0),
  };

  const clear = () => {
    for (const p of photos) void deleteDealPhoto(p);
    setDeal(EMPTY);
  };

  /** Anything worth keeping in the open deal: items, photos or notes. */
  const hasDeal = kind !== "empty" || photos.length > 0 || Boolean(deal.notes?.trim());
  const parkEntry = (state: DealState, name: string): ParkedDeal => ({ id: crypto.randomUUID(), name: name.trim() || parkedDealName(new Date()), savedAt: new Date().toISOString(), state: { ...EMPTY, ...state } });
  /** Set the open deal aside (photos and notes go with it) and start a fresh one. */
  const park = (name: string) => {
    const entry = parkEntry(deal, name);
    setParked((cur) => [entry, ...(cur ?? [])]);
    setDeal(EMPTY);
    setParking(false);
    toast(`Parked “${entry.name}”`);
  };
  /** Pick a parked deal back up; an open one is parked first (the list asks before this runs). */
  const resume = (p: ParkedDeal) => {
    const current = hasDeal ? parkEntry(deal, "") : null;
    setParked((cur) => [...(current ? [current] : []), ...(cur ?? []).filter((x) => x.id !== p.id)]);
    setDeal({ ...EMPTY, ...p.state });
    setParkedOpen(false);
    toast(current ? `Parked the open deal and resumed “${p.name}”` : `Resumed “${p.name}”`);
  };
  const deleteParked = (p: ParkedDeal) => {
    for (const path of p.state.photos ?? []) void deleteDealPhoto(path);
    setParked((cur) => (cur ?? []).filter((x) => x.id !== p.id));
  };

  const close = async () => {
    if (unpriced || kind === "empty") return;
    setClosing(true);
    const note = `Show deal (${KIND_NOUN[kind].toLowerCase()})`;
    try {
      for (const item of deal.out) {
        const unit = unitPrice(item, rate.out)!;
        const h = item.holdingKey ? byKey.get(item.holdingKey) : undefined;
        if (h) {
          await addTransaction({ ...h.identity, type: "sale", date: today, quantity: item.qty, unitPrice: unit, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: note });
        } else if (!item.custom && item.cost !== null && item.cost !== undefined) {
          // Not in Holo, but you said what you paid: record that purchase, then the sale.
          if (!data.products[item.product.id]) await importProduct(item.product.id, item.printing ?? null, item.product.kind);
          const identity = { productId: item.product.id, printing: item.printing ?? null, condition: (item.product.kind === "sealed" ? "Sealed" : "Near Mint") as Condition, grade: item.grade ?? null };
          await addTransaction({ ...identity, type: "purchase", date: today, quantity: item.qty, unitPrice: item.cost, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: "Added from a deal" });
          await addTransaction({ ...identity, type: "sale", date: today, quantity: item.qty, unitPrice: unit, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: note });
        }
      }
      for (const item of deal.in) {
        if (!tracked(item, "in")) continue;
        const h = item.holdingKey ? byKey.get(item.holdingKey) : undefined;
        // Catalog items need saving before they can be held.
        if (!h && !data.products[item.product.id]) await importProduct(item.product.id, item.printing ?? null, item.product.kind);
        const identity = h?.identity ?? { productId: item.product.id, printing: item.printing ?? null, condition: (item.product.kind === "sealed" ? "Sealed" : "Near Mint") as Condition, grade: item.grade ?? null };
        // What you give for it becomes its cost, so later profit is measured from the deal.
        await addTransaction({ ...identity, type: "purchase", date: today, quantity: item.qty, unitPrice: unitPrice(item, rate.in)!, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: note });
      }
      const record: DealRecord = {
        id: crypto.randomUUID(),
        at: new Date().toISOString(),
        kind,
        inValue: totals.inValue,
        outValue: totals.outValue,
        balance: totals.balance,
        profit: totals.profit,
        equity: totals.equity,
        ahead: totals.ahead,
        uncosted: totals.uncosted,
        items: deal.in.length + deal.out.length,
        lines: recordLines(deal, rate, tracked),
        photos: photos.length ? photos : undefined,
        notes: deal.notes?.trim() || undefined,
      };
      setLog([record, ...log].slice(0, 500));
      setRecorded({ record, totals, deal });
      setConfirming(false);
      setDeal(EMPTY);
    } catch (err) {
      toast.error("Couldn't record the deal", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setClosing(false);
    }
  };

  return (
    <div className="animate-fade-in pb-36 lg:pb-0">
      <PageHeader
        title="Deal"
        subtitle="Buys, sells and trades at the table"
        actions={
          <div className="flex gap-1">
            <Button variant="ghost" size="icon" aria-label="Closed deals" onClick={() => setHistoryOpen(true)}>
              <History />
            </Button>
            <Button variant="ghost" size="icon" aria-label="Deal settings" onClick={() => setRatesOpen(true)}>
              <SlidersHorizontal />
            </Button>
            <Button variant="ghost" size="icon" aria-label="Customer view" onClick={() => setCustomer(true)} disabled={kind === "empty"}>
              <Eye />
            </Button>
          </div>
        }
      />

      {todays.length > 0 && <TodayStrip deals={todays} onOpen={() => setHistoryOpen(true)} />}
      {parked.length > 0 && (
        <button type="button" onClick={() => setParkedOpen(true)} className="mb-4 inline-flex items-center gap-2 rounded-full bg-surface px-3.5 py-1.5 text-[13px] font-semibold ring-1 ring-inset ring-border hover:bg-surface-2">
          <Bookmark className="size-3.5 text-[var(--lime)]" /> Parked <span className="tabular text-muted">({parked.length})</span>
        </button>
      )}

      <Balance totals={totals} kind={kind} roundTo={roundTo} onRound={roundCash} />

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        {(["in", "out"] as const).map((side) => (
          <SideCard
            key={side}
            side={side}
            items={deal[side]}
            rate={side === "in" ? rate.in : rate.out}
            rateDefault={side === "in" ? defaults.in : defaults.out}
            total={side === "in" ? totals.inValue : totals.outValue}
            result={kind === "empty" ? null : summary}
            costOf={side === "out" ? costOf : undefined}
            tracked={(i) => tracked(i, side)}
            askCost={rates.askCost ?? true}
            onRate={(r) => setDeal((cur) => ({ ...EMPTY, ...cur, [side === "in" ? "rateIn" : "rateOut"]: r }))}
            onChange={(items) => update(side, items)}
            onAdd={() => setPicking(side)}
            onScan={() => setScanning(side)}
            onEbay={setEbayItem}
            gradeOf={(i) => i.grade ?? (i.holdingKey ? byKey.get(i.holdingKey)?.identity.grade : null) ?? null}
          />
        ))}
      </div>

      <section className="mt-8">
        <h2 className="flex items-center gap-2 font-display text-[18px] leading-none ">
          <Camera className="size-5 text-[var(--lime)]" /> Photos {photos.length > 0 && <span className="font-mono text-[12px] text-subtle">{photos.length}</span>}
        </h2>
        <p className="mt-1 text-[12px] text-muted">Document the deal: the cards on the table, a receipt, the customer&apos;s binder</p>
        <DealPhotos photos={photos} onChange={setPhotos} className="mt-3 max-w-xl" />
      </section>

      <section className="mt-8 max-w-xl">
        <h2 className="flex items-center gap-2 font-display text-[18px] leading-none ">
          <StickyNote className="size-5 text-[var(--lime)]" /> Notes
        </h2>
        <NotesField className="mt-3" value={deal.notes ?? ""} onChange={(v) => setDeal((cur) => ({ ...EMPTY, ...cur, notes: v || undefined }))} placeholder="Who it was with, how they paid, anything to remember" />
      </section>

      {/* Close bar: pinned above the tab bar on phones. */}
      {kind !== "empty" && (
        <div className="fixed inset-x-0 bottom-[calc(4.5rem+env(safe-area-inset-bottom))] z-30 px-4 lg:static lg:mt-6 lg:px-0">
          <div className="mx-auto max-w-[640px] rounded-2xl border border-border bg-surface/95 p-2 shadow-2xl shadow-black/50 backdrop-blur-xl lg:max-w-none lg:border-0 lg:bg-transparent lg:p-0 lg:shadow-none">
            <p className="tabular truncate px-2 pb-2 pt-1 text-center text-[13px] font-semibold lg:text-left">
              {cashLine(totals.balance)}
              {totals.ahead !== null ? (
                <>
                  <span className="text-muted"> · {totals.ahead < 0 ? "Behind" : "Ahead"} </span>
                  <span className={totals.ahead >= 0 ? "text-up" : "text-down"}>{signedMoney(totals.ahead)}</span>
                </>
              ) : (
                net !== null && (
                  <>
                    <span className="text-muted"> · </span>
                    <span className={net >= 0 ? "text-up" : "text-down"}>You&apos;re {signedMoney(net)}</span>
                  </>
                )
              )}
            </p>
            <div className="flex gap-2">
              <Button variant="secondary" size="lg" onClick={clear}>
                Clear
              </Button>
              <Button variant="secondary" size="lg" onClick={() => setParking(true)} aria-label="Park this deal to finish later">
                <Bookmark /> <span className="hidden sm:inline">Park</span>
              </Button>
              <Button variant="lime" size="lg" className="flex-1" disabled={unpriced} onClick={() => setConfirming(true)}>
                {unpriced ? "Price every item to close" : `Close ${KIND_NOUN[kind].toLowerCase()}`}
              </Button>
            </div>
          </div>
        </div>
      )}

      <DealPicker side={picking} onClose={() => setPicking(null)} onPick={(item) => picking && add(picking, item)} />
      <SettingsDialog open={ratesOpen} onOpenChange={setRatesOpen} rates={rates} onSave={setRates} />
      <ScanSheet
        open={scanning !== null}
        onOpenChange={(o) => !o && setScanning(null)}
        title={scanning === "out" ? "Scan going out" : "Scan coming in"}
        description={scanning === "out" ? "Each card you scan joins the deal; ones not in Holo are marked so." : "Each card you scan joins the deal at the current rate."}
        onPick={(pick) => addScan(scanning ?? "in", pick)}
      />
      <Dialog open={ebayItem !== null} onOpenChange={(o) => !o && setEbayItem(null)}>
        <DialogContent className="sm:max-w-[560px]">
          <DialogHeader>
            <DialogTitle className="truncate pr-6">{ebayItem?.product.name}</DialogTitle>
            <DialogDescription>What it&apos;s actually selling for.</DialogDescription>
          </DialogHeader>
          <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6">
            {ebayItem && <EbaySales bare productId={ebayItem.product.id} name={ebayItem.product.name} market={ebayItem.holdingKey ? undefined : ebayItem.market} printing={ebayItem.printing ?? null} grade={ebayItem.grade ?? (ebayItem.holdingKey ? byKey.get(ebayItem.holdingKey)?.identity.grade : null) ?? null} />}
          </div>
        </DialogContent>
      </Dialog>
      <CloseDialog open={confirming} onOpenChange={setConfirming} kind={kind} totals={totals} deal={deal} rate={rate} effects={effects} closing={closing} onClose={() => void close()} />
      <RecordedDialog recorded={recorded} onDone={() => setRecorded(null)} />
      <HistoryDialog
        open={historyOpen}
        onOpenChange={setHistoryOpen}
        deals={log}
        onPhotos={(id, next) => setLog((cur) => cur.map((d) => (d.id === id ? { ...d, photos: next.length ? next : undefined } : d)))}
        onNotes={(id, next) => setLog((cur) => cur.map((d) => (d.id === id ? { ...d, notes: next.trim() || undefined } : d)))}
        parked={parked}
        hasDeal={hasDeal}
        onResume={(p) => {
          resume(p);
          setHistoryOpen(false);
        }}
        onDelete={deleteParked}
      />
      <ParkDialog open={parking} onOpenChange={setParking} onPark={park} />
      <ParkedDialog open={parkedOpen} onOpenChange={setParkedOpen} parked={parked} hasDeal={hasDeal} onResume={resume} onDelete={deleteParked} />
      <CustomerView open={customer} onOpenChange={setCustomer} deal={deal} rate={rate} totals={totals} />
    </div>
  );
}

function cashLine(balance: number) {
  return Math.abs(balance) < 0.005 ? "Even swap" : balance > 0 ? `Customer pays you ${money(balance)}` : `You pay ${money(-balance)}`;
}

/** A small label you can hover for what it means. */
function Term({ label, text, className }: { label: string; text: string; className?: string }) {
  return (
    <Hint content={<span className="block max-w-[260px]">{text}</span>}>
      <span className={cn("inline-flex cursor-help items-center gap-1 font-mono text-[10px] uppercase tracking-[0.06em]", className)}>
        {label} <Info className="size-3 opacity-70" />
      </span>
    </Hint>
  );
}

/* ------------------------------- Balance ---------------------------------- */

function Balance({ totals, kind, roundTo, onRound }: { totals: DealTotals; kind: DealKind; roundTo: number | null; onRound: () => void }) {
  const { balance } = totals;
  const even = Math.abs(balance) < 0.005;
  const ahead = totals.ahead;
  const net = ahead ?? dealNet(totals);
  const verdict = ahead !== null ? `${aheadTitle(ahead)} ${signedMoney(ahead)}` : dealVerdict(totals);
  const onPaper = ahead !== null && showsEquity(totals) && totals.equity > 0.005 ? totals.equity : null;
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
      {verdict && (
        <Hint content={<span className="block max-w-[260px]">{ahead !== null ? TERMS.ahead : TERMS.verdict}</span>}>
          <p className={cn("mt-4 inline-flex cursor-help items-center gap-2 rounded-full bg-[#0b0b0c] px-3.5 py-2 text-[15px] font-bold", (net ?? 0) >= 0 ? "text-[var(--lime)]" : "text-down")}>
            {(net ?? 0) >= 0 ? <ArrowUpRight className="size-4" /> : <ArrowDownRight className="size-4" />} {verdict}
          </p>
        </Hint>
      )}
      {onPaper !== null && <p className="mt-2 text-[12px] text-muted">Includes {money(onPaper)} on paper</p>}
      <div className="mt-4">
        <Term label={kind === "empty" ? "Add items to start" : even ? "Settled · no cash" : balance > 0 ? "Customer pays you" : "You pay the customer"} text={TERMS.cash} className="text-subtle" />
      </div>
      <div className="mt-1 flex items-center justify-between gap-3">
        <p className="hype-num tabular text-[56px] leading-none sm:text-[68px]">{money(Math.abs(balance))}</p>
        {roundTo !== null && (
          <button type="button" onClick={onRound} className="btn-3d btn-3d-dark shrink-0 rounded-full bg-surface-2 px-4 py-2 text-center hover:bg-surface-3">
            <span className="block text-[10px] font-semibold text-muted">Round to</span>
            <span className="tabular block text-[14px] font-bold">{money(Math.abs(roundTo))}</span>
          </button>
        )}
      </div>
      {totals.uncosted > 0 && kind !== "empty" && <p className="mt-2 text-[12px] text-muted">Add what you paid for every item to see your total</p>}
      <dl className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Coming in" term={TERMS.comingIn} value={money(totals.inValue)} />
        <Stat label="Going out" term={TERMS.goingOut} value={money(totals.outValue)} />
        <Stat label="Sale profit" term={TERMS.profit} value={totals.profit === null ? "—" : <span className={totals.profit >= 0 ? "text-up" : "text-down"}>{signedMoney(totals.profit)}</span>} />
        <Stat label="Trade-in value" term={TERMS.value} value={!showsEquity(totals) ? "—" : <span className={totals.equity >= 0 ? "text-up" : "text-down"}>{signedMoney(totals.equity)}</span>} />
      </dl>
    </section>
  );
}

function Stat({ label, term, value }: { label: string; term: string; value: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt>
        <Term label={label} text={term} className="text-subtle" />
      </dt>
      <dd className="tabular mt-1 truncate text-[16px] font-semibold">{value}</dd>
    </div>
  );
}

function TodayStrip({ deals, onOpen }: { deals: DealRecord[]; onOpen: () => void }) {
  const cash = deals.reduce((s, d) => s + d.balance, 0);
  const profit = deals.reduce((s, d) => s + (d.profit ?? 0), 0);
  const known = deals.map(recordAhead).filter((n): n is number => n !== null);
  const ahead = known.reduce((s, n) => s + n, 0);
  return (
    <button type="button" onClick={onOpen} className="tabular mb-4 flex w-full flex-wrap items-center gap-x-5 gap-y-1 text-left text-[13px] text-muted hover:text-foreground">
      <span className="font-mono text-[11px] uppercase tracking-[0.06em] text-subtle">Today</span>
      <span>
        <span className="font-semibold text-foreground">{deals.length}</span> deal{deals.length === 1 ? "" : "s"}
      </span>
      <span className={known.length ? undefined : "hidden"}>
        Ahead <span className={cn("font-semibold", ahead >= 0 ? "text-up" : "text-down")}>{signedMoney(ahead)}</span>
      </span>
      <span>
        Cash <span className={cn("font-semibold", cash >= 0 ? "text-up" : "text-down")}>{signedMoney(cash)}</span>
      </span>
      <span>
        Profit <span className={cn("font-semibold", profit >= 0 ? "text-up" : "text-down")}>{signedMoney(profit)}</span>
      </span>
      <span className="ml-auto text-[12px] text-subtle">See all</span>
    </button>
  );
}

/* --------------------------------- Sides ---------------------------------- */

function SideCard({
  side,
  items,
  rate,
  rateDefault,
  total,
  result,
  costOf,
  tracked,
  askCost,
  onRate,
  onChange,
  onAdd,
  onScan,
  onEbay,
  gradeOf,
}: {
  side: DealSide;
  items: DealItem[];
  rate: number;
  rateDefault: number;
  total: number;
  /** What the deal comes to, shown under the slider as you drag. */
  result: string | null;
  costOf?: (item: DealItem) => number | null;
  tracked: (item: DealItem) => boolean;
  askCost: boolean;
  onRate: (r: number | null) => void;
  onChange: (items: DealItem[]) => void;
  onAdd: () => void;
  onScan: () => void;
  onEbay: (item: DealItem) => void;
  /** A line's grade: its own, or the holding's it came from. */
  gradeOf: (item: DealItem) => Grade | null;
}) {
  const set = (key: string, patch: Partial<DealItem>) => onChange(items.map((i) => (i.key === key ? { ...i, ...patch } : i)));
  const Icon = side === "in" ? ArrowDownLeft : ArrowUpRight;
  const [showCost, setShowCost] = useState<Set<string>>(new Set());
  return (
    <section className="min-w-0">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="flex items-center gap-2 font-display text-[18px] leading-none ">
            <Icon className={cn("size-5", side === "in" ? "text-up" : "text-[var(--plan-pink)]")} />
            {side === "in" ? "Coming in" : "Going out"}
          </h2>
          <p className="mt-1 text-[12px] text-muted">{side === "in" ? "What the customer hands you" : "What you hand over"}</p>
        </div>
        <p className="hype-num tabular text-[26px] leading-none">{money(total)}</p>
      </div>

      {/* Counter-offer slider: drag the rate and watch the deal move. */}
      <div className="mt-4 rounded-2xl bg-surface p-3.5 ring-1 ring-inset ring-border">
        <div className="flex items-baseline justify-between">
          <Hint content={<span className="block max-w-[260px]">{TERMS.rate}</span>}>
            <span className="inline-flex cursor-help items-center gap-1 text-[13px] font-medium">
              At <span className="tabular">{pct(rate, 0)}</span> of market <Info className="size-3 text-subtle" />
            </span>
          </Hint>
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
        {result && <p className="tabular mt-1.5 truncate text-[12px] text-muted">↳ {result}</p>}
      </div>

      <ul className="mt-3 space-y-2">
        {items.map((item) => {
          const cost = costOf?.(item) ?? null;
          const p = unitPrice(item, rate);
          const lineTotal = p === null ? null : p * item.qty;
          const profit = cost !== null && lineTotal !== null ? lineTotal - cost : null;
          const notInHolo = side === "out" && !item.holdingKey && !item.custom;
          const isTracked = tracked(item);
          const slab = gradeOf(item);
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
                {/* Market struck through, then the price it goes at, and the share as a chip. */}
                <p className="tabular mt-0.5 flex flex-wrap items-center gap-x-1.5 text-[12px] text-muted">
                  {item.market !== null && p !== null && Math.abs(p - item.market) > 0.004 ? (
                    <>
                      <span className="text-subtle line-through">{money(item.market)}</span>
                      <span className="text-subtle">→</span>
                      <span className="font-semibold text-foreground">{money(p)}</span>
                      <span className="rounded-full bg-[var(--lime)] px-1.5 text-[10px] font-bold text-[#0b0b0c]">{Math.round((p / item.market) * 100)}%</span>
                    </>
                  ) : item.custom ? (
                    <span>Custom item</span>
                  ) : (
                    <span>Market {money(item.market)}</span>
                  )}
                  {item.grade && <span>· {item.grade.company} {item.grade.grade}</span>}
                  {(item.product.source === "tcgapi" || item.product.source === "sample") && (
                    <>
                      <span>·</span>
                      <button type="button" onClick={() => onEbay(item)} className="font-medium text-foreground/80 underline-offset-2 hover:text-foreground hover:underline">
                        eBay sold
                      </button>
                    </>
                  )}
                </p>
                {/* How easily it sells, only when its eBay sales are already on this device. */}
                {!item.custom && <SellSpeedTag productId={item.product.id} printing={item.printing ?? null} grade={slab ? gradeLabel(slab) : null} name={item.product.name} market={item.market} className="mt-1" />}
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
                  {/* This item's own rate: overrides the slider for just this row. Typing a price clears it, and vice versa. */}
                  <span className="relative">
                    <input
                      inputMode="numeric"
                      aria-label="Percent of market for this item"
                      value={item.rate !== null && item.rate !== undefined ? String(Math.round(item.rate * 100)) : ""}
                      placeholder={item.price !== null || item.market === null ? "—" : String(Math.round(lineRate(item, rate) * 100))}
                      disabled={item.market === null}
                      onChange={(e) => {
                        const v = e.target.value.replace(/[^0-9]/g, "").slice(0, 3);
                        set(item.key, { rate: v === "" ? null : Number(v) / 100, price: null });
                      }}
                      className={cn("tabular h-7 w-[3.75rem] rounded-full pl-2.5 pr-5 text-[13px] outline-none placeholder:text-foreground/70 focus:bg-surface-3 disabled:opacity-40", item.rate !== null && item.rate !== undefined ? "bg-surface-3 ring-1 ring-[var(--lime)]/60" : "bg-surface-2")}
                    />
                    <span className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-[12px] text-subtle">%</span>
                  </span>
                  <span className="relative">
                    <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-[13px] text-subtle">$</span>
                    <input
                      inputMode="decimal"
                      aria-label="Price each"
                      value={item.price ?? ""}
                      placeholder={p === null ? "Price" : p.toFixed(2)}
                      onChange={(e) => {
                        const v = e.target.value.replace(/[^0-9.]/g, "");
                        set(item.key, { price: v === "" ? null : Number(v), rate: null });
                      }}
                      className={cn("tabular h-7 w-24 rounded-full pl-6 pr-2 text-[13px] outline-none placeholder:text-foreground/70 focus:bg-surface-3", item.price !== null ? "bg-surface-3 ring-1 ring-[var(--lime)]/60" : "bg-surface-2")}
                    />
                  </span>
                  <span className="text-[11px] text-subtle">each</span>
                  {(item.price !== null || (item.rate !== null && item.rate !== undefined)) && (
                    <button className="text-[11px] text-muted underline-offset-2 hover:text-foreground hover:underline" onClick={() => set(item.key, { price: null, rate: null })}>
                      Use {pct(rate, 0)}
                    </button>
                  )}
                </div>
                {/* What happens to this line in your collection. */}
                {item.custom ? (
                  <p className="mt-2 text-[11px] font-medium text-subtle">Custom · not tracked</p>
                ) : side === "in" ? (
                  <button
                    type="button"
                    role="switch"
                    aria-checked={isTracked}
                    aria-label="Add to collection"
                    onClick={() => set(item.key, { track: !isTracked })}
                    className={cn("mt-2 inline-flex h-[26px] items-center gap-1.5 rounded-full px-2.5 text-[12px] font-medium ring-1 ring-inset transition-colors", isTracked ? "bg-[var(--lime)]/15 text-foreground ring-[var(--lime)]/50" : "text-muted ring-white/12 hover:text-foreground")}
                  >
                    {isTracked ? <Check className="size-3" /> : <Plus className="size-3" />}
                    {isTracked ? "Adding to collection" : "Add to collection"}
                  </button>
                ) : notInHolo ? (
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <span className="rounded-full bg-surface-2 px-2 py-0.5 text-[11px] font-semibold text-muted">{isTracked ? "Not in Holo · will be added" : "Not in Holo · not tracked"}</span>
                    {askCost || showCost.has(item.key) || item.cost !== null && item.cost !== undefined ? (
                      <span className="relative">
                        <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-[12px] text-subtle">Paid $</span>
                        <input
                          inputMode="decimal"
                          aria-label="What you paid each"
                          value={item.cost ?? ""}
                          placeholder="each"
                          onChange={(e) => {
                            const v = e.target.value.replace(/[^0-9.]/g, "");
                            set(item.key, { cost: v === "" ? null : Number(v) });
                          }}
                          className={cn("tabular h-7 w-28 rounded-full pl-[3.25rem] pr-2 text-[12px] outline-none focus:bg-surface-3", item.cost !== null && item.cost !== undefined ? "bg-surface-3 ring-1 ring-[var(--lime)]/60" : "bg-surface-2")}
                        />
                      </span>
                    ) : (
                      <button className="text-[12px] font-medium underline-offset-2 hover:underline" onClick={() => setShowCost(new Set([...showCost, item.key]))}>
                        Add what you paid
                      </button>
                    )}
                  </div>
                ) : null}
                {side === "out" && (cost !== null || !notInHolo) && (
                  <p className="tabular mt-2 text-[12px] text-muted">
                    {item.holdingKey ? <>You paid {cost === null ? "—" : money(cost)}</> : "Profit"}
                    {profit !== null && (
                      <>
                        {item.holdingKey ? " · " : " "}
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
      <div className="mt-2 flex gap-2">
        <Button variant="secondary" className="flex-1" onClick={onAdd}>
          <Plus /> {side === "in" ? "Add what's coming in" : "Add from inventory"}
        </Button>
        {/* Scanning needs a phone camera, so it's not offered on desktop. */}
        <Button variant="secondary" className="lg:hidden" onClick={onScan} aria-label={side === "in" ? "Scan what's coming in" : "Scan what's going out"}>
          <ScanLine /> Scan
        </Button>
      </div>
    </section>
  );
}

/* ------------------------------ Settings ---------------------------------- */

function SettingsDialog({ open, onOpenChange, rates, onSave }: { open: boolean; onOpenChange: (o: boolean) => void; rates: DealRates; onSave: (r: DealRates) => void }) {
  const rows: { key: "buy" | "trade" | "sell"; label: string; hint: string }[] = [
    { key: "buy", label: "Buying", hint: "What you pay for items you buy outright" },
    { key: "trade", label: "Trade-in", hint: "What you credit for items taken in on trade" },
    { key: "sell", label: "Selling", hint: "What you charge for items going out" },
  ];
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[440px]">
        <DialogHeader>
          <DialogTitle>Deal settings</DialogTitle>
          <DialogDescription>Rates as a share of market. Every new deal starts here; drag a side&apos;s slider to counter.</DialogDescription>
        </DialogHeader>
        <div className="space-y-5 overflow-y-auto px-6 pb-6 pt-2">
          <label className="flex items-center justify-between gap-4">
            <span>
              <span className="block text-[14px] font-medium">Add what comes in to my collection</span>
              <span className="block text-[12px] text-muted">You can still switch any item in or out on the deal.</span>
            </span>
            <Switch checked={rates.addIncoming ?? true} onCheckedChange={(on) => onSave({ ...rates, addIncoming: on })} />
          </label>
          <label className="flex items-center justify-between gap-4">
            <span>
              <span className="block text-[14px] font-medium">Ask what I paid for things not in Holo</span>
              <span className="block text-[12px] text-muted">With it, they&apos;re recorded properly and their profit is known.</span>
            </span>
            <Switch checked={rates.askCost ?? true} onCheckedChange={(on) => onSave({ ...rates, askCost: on })} />
          </label>
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

/* ------------------------------- Closing ---------------------------------- */

/** Before a deal closes: who pays whom, each side's items, profit and value, and what happens to your collection. */
function CloseDialog({
  open,
  onOpenChange,
  kind,
  totals,
  deal,
  rate,
  effects,
  closing,
  onClose,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  kind: DealKind;
  totals: DealTotals;
  deal: DealState;
  rate: { in: number; out: number };
  effects: { adds: number; sells: number; untracked: number };
  closing: boolean;
  onClose: () => void;
}) {
  const verdict = dealVerdict(totals);
  const net = dealNet(totals);
  const what = [effects.adds ? `Adds ${effects.adds} to your collection` : null, effects.sells ? `sells ${effects.sells} from it` : null, effects.untracked ? `${effects.untracked} not tracked` : null].filter(Boolean).join(" · ");
  const side = (items: DealItem[], r: number, label: string, incoming: boolean) =>
    items.length > 0 && (
      <div className="rounded-2xl bg-surface-2 p-3.5">
        <div className="flex items-center justify-between text-[14px] font-semibold">
          <span className="flex items-center gap-2">
            {incoming ? <ArrowDownLeft className="size-4 text-up" /> : <ArrowUpRight className="size-4 text-[var(--plan-pink)]" />} {label}
            <span className="font-normal text-muted">
              {items.reduce((s, i) => s + i.qty, 0)} item{items.reduce((s, i) => s + i.qty, 0) === 1 ? "" : "s"}
            </span>
          </span>
          <span className="tabular">{money(items.reduce((s, i) => s + (unitPrice(i, r) ?? 0) * i.qty, 0))}</span>
        </div>
        <div className="mt-2 flex -space-x-2.5">
          {items.slice(0, 8).map((i) => (
            <ProductImage key={i.key} product={i.product} size="xs" className="h-12 w-[34px] rounded-md shadow-lg shadow-black/40" />
          ))}
        </div>
      </div>
    );
  return (
    <Dialog open={open} onOpenChange={(o) => !closing && onOpenChange(o)}>
      <DialogContent className="sm:max-w-[480px]">
        <DialogHeader>
          <DialogTitle className="font-display text-[22px] leading-none">Close this {KIND_NOUN[kind].toLowerCase()}?</DialogTitle>
          <DialogDescription>{what}</DialogDescription>
        </DialogHeader>
        <div className="space-y-3 overflow-y-auto px-6 pb-6">
          <div className="rounded-2xl bg-surface-2 p-4">
            <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{Math.abs(totals.balance) < 0.005 ? "Even trade" : totals.balance > 0 ? "Customer pays you" : "You pay the customer"}</p>
            <p className="hype-num tabular mt-1 text-[48px] leading-none">{money(Math.abs(totals.balance))}</p>
          </div>
          {totals.ahead !== null ? (
            <div>
              <p className="flex items-center gap-2 text-[16px] font-bold">
                {totals.ahead >= 0 ? <ArrowUpRight className="size-4 text-up" /> : <ArrowDownRight className="size-4 text-down" />} {aheadTitle(totals.ahead)}{" "}
                <span className={cn("tabular", totals.ahead >= 0 ? "text-up" : "text-down")}>{signedMoney(totals.ahead)}</span>
              </p>
              <AheadBreakdown profit={totals.profit} equity={showsEquity(totals) ? totals.equity : null} className="mt-1 pl-6" />
            </div>
          ) : (
            verdict && <p className={cn("flex items-center gap-2 text-[16px] font-bold", (net ?? 0) >= 0 ? "text-up" : "text-down")}>{(net ?? 0) >= 0 ? <ArrowUpRight className="size-4" /> : <ArrowDownRight className="size-4" />} {verdict}</p>
          )}
          {totals.uncosted > 0 && <p className="text-[13px] text-muted">Add what you paid for every item to see your total</p>}
          {side(deal.in, rate.in, "Coming in", true)}
          {side(deal.out, rate.out, "Going out", false)}
          <div className="flex gap-2 pt-2">
            <Button variant="secondary" size="lg" disabled={closing} onClick={() => onOpenChange(false)}>
              Keep editing
            </Button>
            <Button variant="lime" size="lg" className="flex-1" disabled={closing} onClick={onClose}>
              {closing && <Loader2 className="animate-spin" />}
              {closing ? "Recording…" : `Close ${KIND_NOUN[kind].toLowerCase()}`}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** The deal, recorded: an electric-lime card (pink if it left you behind) with how far ahead you came out and what changed hands. */
function RecordedDialog({ recorded, onDone }: { recorded: { record: DealRecord; totals: DealTotals; deal: DealState } | null; onDone: () => void }) {
  if (!recorded) return null;
  const { record, totals, deal } = recorded;
  const ahead = totals.ahead;
  // The headline figure decides the color: down turns the whole card pink (never pink on lime).
  const down = (showsEquity(totals) && totals.equity < -0.005) || (ahead !== null && ahead < -0.005);
  const headline = totals.profit !== null ? { label: "Sale profit", value: totals.profit } : totals.inValue > 0 ? { label: "Trade-in value", value: totals.equity } : null;
  const items = [...deal.out, ...deal.in].slice(0, 7);
  return (
    <Dialog open onOpenChange={(o) => !o && onDone()}>
      <DialogContent hideClose className={cn("overflow-hidden border-0 sm:max-w-[460px]", down ? "bg-[var(--plan-pink)] text-white" : "bg-[var(--lime)] text-[#0b0b0c]")} aria-describedby={undefined}>
        <div className="flex flex-col items-center px-6 pb-6 pt-10 text-center">
          <span className={cn("flex size-20 items-center justify-center rounded-full", down ? "bg-white text-[var(--plan-pink)]" : "bg-[#0b0b0c] text-[var(--lime)]")}>
            <Check className="size-9" strokeWidth={1.75} />
          </span>
          <p className="mt-5 font-mono text-[11px] uppercase tracking-[0.14em] opacity-60">In your collection</p>
          <DialogTitle className="mt-1 font-display text-[38px] leading-[0.92]">
            {KIND_NOUN[record.kind]}
            <br />
            recorded
          </DialogTitle>
          {items.length > 0 && (
            <div className="relative mt-6 h-28 w-full">
              {items.map((i, n) => {
                const off = n - (items.length - 1) / 2;
                return (
                  <span key={i.key} className="absolute left-1/2 top-0 origin-bottom" style={{ transform: `translateX(calc(-50% + ${off * 34}px)) rotate(${off * 9}deg)` }}>
                    <ProductImage product={i.product} size="sm" className="h-24 w-[68px] rounded-md shadow-xl shadow-black/30" />
                  </span>
                );
              })}
            </div>
          )}
          {ahead !== null ? (
            <>
              <p className="mt-4 font-display text-[22px] leading-none tracking-[-0.02em]">{aheadTitle(ahead, true)}</p>
              <p className="hype-num tabular mt-1 text-[64px] leading-none">{signedMoney(ahead)}</p>
              <AheadBreakdown profit={totals.profit} equity={showsEquity(totals) ? totals.equity : null} plain className="mt-2 justify-center text-center" />
            </>
          ) : (
            headline && (
              <>
                <p className="mt-4 font-mono text-[11px] uppercase tracking-[0.14em] opacity-60">{headline.label}</p>
                <p className="hype-num tabular text-[64px] leading-none">{signedMoney(headline.value)}</p>
                {totals.uncosted > 0 && <p className="mt-2 text-[12px] font-medium opacity-70">Total unknown: not every item had a cost</p>}
              </>
            )
          )}
          <div className="mt-5 flex flex-wrap justify-center gap-1.5">
            {[cashLine(totals.balance).replace("Customer pays you", "They paid"), `${record.items} item${record.items === 1 ? "" : "s"}`, record.photos?.length ? `${record.photos.length} photo${record.photos.length === 1 ? "" : "s"}` : null]
              .filter(Boolean)
              .map((t) => (
                <span key={t} className={cn("tabular rounded-full px-3 py-1.5 text-[13px] font-semibold", down ? "bg-white text-[var(--plan-pink)]" : "bg-[#0b0b0c] text-[var(--lime)]")}>
                  {t}
                </span>
              ))}
          </div>
          <button type="button" onClick={onDone} className={cn("mt-7 h-12 w-full rounded-full text-[16px] font-semibold", down ? "bg-white text-[var(--plan-pink)]" : "bg-[#0b0b0c] text-[var(--lime)]")}>
            Done
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/* ----------------------------- Customer view ------------------------------ */

/** Tile measures for a number of columns: width, and height with the name and price under it. */
function customerTile(cols: number, width: number) {
  const w = (width - (cols - 1) * 12) / cols;
  return { w, h: (w * 88) / 63 + (cols >= 4 ? 28 : cols === 3 ? 52 : 70) };
}

/** The fewest columns (2 to 6) that fit every card in the space above the pinned cash panel. */
function customerColumns(counts: number[], width: number, room: number) {
  for (let c = 2; c <= 6; c++) {
    const t = customerTile(c, width);
    const rows = counts.reduce((s, n) => s + Math.ceil(n / c), 0);
    if (rows * t.h + Math.max(0, rows - counts.length) * 14 <= room) return c;
  }
  return 6;
}

const CUSTOMER_TITLE: Record<DealKind, string> = { buy: "We're buying", sell: "You're buying", trade: "Your trade", empty: "Your trade" };

/**
 * What the customer sees, full screen and calm: a receipt-style header, their cards (what they
 * hand you, what they get) as tiles at the price you're paying or charging, and the cash pinned
 * at the bottom (lime when we pay them). Tiles shrink as cards are added so the cash always shows.
 * Click a card for a closer look. Flip turns the page around for someone across the table; the
 * buttons stay the right way up for you. Never market prices, rates, your costs, profit or value gained.
 */
function CustomerView({ open, onOpenChange, deal, rate, totals }: { open: boolean; onOpenChange: (o: boolean) => void; deal: DealState; rate: { in: number; out: number }; totals: DealTotals }) {
  const [flipped, setFlipped] = useState(false);
  const [looking, setLooking] = useState<{ item: DealItem; incoming: boolean } | null>(null);
  const [area, setArea] = useState({ w: 0, h: 0 });
  const observer = useRef<ResizeObserver | null>(null);
  const measure = useCallback((el: HTMLDivElement | null) => {
    observer.current?.disconnect();
    if (!el) return;
    observer.current = new ResizeObserver(([e]) => setArea({ w: e.contentRect.width, h: e.contentRect.height }));
    observer.current.observe(el);
  }, []);
  const kind = dealKind(deal.in.length, deal.out.length);
  const counts = [deal.in.length, deal.out.length].filter((n) => n > 0);
  // Room for the tiles: the scroll area less the header (about 100) and each section's heading.
  const cols = area.w ? customerColumns(counts, area.w, area.h - 100 - counts.length * (32 + 44)) : 2;
  const b = totals.balance;
  const even = Math.abs(b) < 0.005;
  const wePay = !even && b < 0;

  const section = (title: string, items: DealItem[], r: number, incoming: boolean, total: number) => {
    const count = items.reduce((s, i) => s + i.qty, 0);
    return (
      <section className="mt-8">
        <div className="flex items-baseline gap-2.5">
          <h3 className="font-display text-[24px] leading-tight tracking-[-0.025em] sm:text-[26px]">{title}</h3>
          <span className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">
            {count} item{count === 1 ? "" : "s"}
          </span>
          <span className="tabular ml-auto text-[18px] font-semibold">{money(total)}</span>
        </div>
        <div className="mt-3.5 grid gap-x-3 gap-y-3.5" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
          {items.map((i) => {
            const each = unitPrice(i, r) ?? 0;
            const priceSize = cols >= 4 ? 14 : cols === 3 ? 18 : 24;
            return (
              <button key={i.key} type="button" disabled={i.custom} onClick={() => setLooking({ item: i, incoming })} className="group min-w-0 text-left disabled:cursor-default">
                <span className="relative block">
                  <ProductImage product={i.product} grade={i.grade} size={cols <= 2 ? "lg" : "md"} className={cn("w-full transition-transform group-enabled:group-hover:-translate-y-0.5", i.product.kind === "sealed" ? "aspect-square rounded-2xl" : "aspect-[63/88] rounded-lg")} />
                  {i.qty > 1 && (
                    <span className={cn("tabular absolute right-1.5 top-1.5 rounded-full bg-black/55 font-semibold text-white ring-1 ring-inset ring-white/15 backdrop-blur", cols >= 4 ? "px-1.5 py-0.5 text-[11px]" : "px-2.5 py-1 text-[14px]")}>×{i.qty}</span>
                  )}
                </span>
                {cols < 4 && <span className={cn("mt-2 block text-muted", cols === 3 ? "truncate text-[12px]" : "line-clamp-2 min-h-[2.6em] text-[14px] leading-snug")}>{i.product.name}</span>}
                <span className="tabular mt-0.5 block truncate font-display leading-tight" style={{ fontSize: priceSize, letterSpacing: `${-priceSize * 0.025}px` }}>
                  {money(each * i.qty)}
                </span>
              </button>
            );
          })}
        </div>
      </section>
    );
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (!o) setFlipped(false);
        onOpenChange(o);
      }}
    >
      <DialogContent className="inset-0 h-[100dvh] max-h-none rounded-none border-0 bg-[#0b0b0c] sm:inset-0 sm:left-0 sm:top-0 sm:max-w-none sm:translate-x-0 sm:rounded-none" hideClose>
        <DialogTitle className="sr-only">Your deal</DialogTitle>
        <DialogDescription className="sr-only">The deal, for the customer: their cards, the prices and the cash.</DialogDescription>
        <div className={cn("relative flex min-h-0 flex-1 flex-col transition-transform duration-500 ease-out motion-reduce:transition-none", flipped && "rotate-180")}>
          {/* The lit grid behind the top, like Home. Still. */}
          <div aria-hidden className="pointer-events-none absolute inset-x-0 top-0 h-[460px] [mask-image:linear-gradient(to_bottom,black_50%,transparent)]">
            <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.05)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.05)_1px,transparent_1px)] bg-[size:36px_36px]" />
            <div className="absolute inset-0 bg-[radial-gradient(300px_at_15%_30%,rgba(212,255,58,0.18),transparent),radial-gradient(280px_at_95%_50%,rgba(47,91,255,0.2),transparent)]" />
          </div>
          <div className="relative min-h-0 flex-1 overflow-y-auto px-5 pt-[72px] sm:px-6">
            <div ref={measure} className="mx-auto h-full max-w-[640px]">
              <div className="flex items-baseline justify-between">
                <span className="font-display text-[20px] tracking-[-0.025em] text-[var(--lime)]">Lucent</span>
                <span className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{new Date().toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}</span>
              </div>
              <h2 className="mt-3 truncate font-display text-[40px] leading-none tracking-[-0.035em] sm:text-[44px]">{CUSTOMER_TITLE[kind]}</h2>
              {deal.in.length > 0 && section("You hand us", deal.in, rate.in, true, totals.inValue)}
              {deal.out.length > 0 && section("You get", deal.out, rate.out, false, totals.outValue)}
              <div className="h-5" />
            </div>
          </div>
          {/* Pinned at the bottom: never scrolled out of sight. */}
          <div className="relative px-5 pb-3 pt-2 sm:px-6">
            <section className={cn("relative mx-auto max-w-[640px] overflow-hidden rounded-[28px] px-5 py-6 text-center", wePay ? "bg-[var(--lime)] text-[#0b0b0c] shadow-[0_0_48px_rgba(212,255,58,0.3)]" : "bg-white/[0.06] ring-1 ring-inset ring-white/10")}>
              {wePay && <div aria-hidden className="absolute inset-0 bg-[linear-gradient(rgba(0,0,0,0.08)_1px,transparent_1px),linear-gradient(90deg,rgba(0,0,0,0.08)_1px,transparent_1px)] bg-[size:28px_28px]" />}
              <p className={cn("relative font-display text-[24px] leading-tight tracking-[-0.025em] sm:text-[26px]", wePay ? "text-[#0b0b0c]/75" : "text-white/80")}>{even ? "Even swap" : wePay ? "We pay you" : "You pay"}</p>
              {even ? <p className="relative mt-2 text-[17px] text-muted">No cash changes hands</p> : <p className="tabular relative mt-1 font-display text-[64px] leading-none tracking-[-0.035em] sm:text-[80px]">{money(Math.abs(b))}</p>}
            </section>
          </div>
        </div>
        {/* The controls stay the right way up for you, at whichever end is yours. */}
        <div className={cn("absolute right-4 z-10 flex gap-2", flipped ? "bottom-3" : "top-3")}>
          <Button variant="secondary" onClick={() => setFlipped((f) => !f)} aria-label="Flip the page for the person across from you">
            <ArrowUpDown /> {flipped ? "Flip back" : "Flip"}
          </Button>
          <Button variant="secondary" onClick={() => onOpenChange(false)}>
            Done
          </Button>
        </div>
        <CustomerCard look={looking} rate={rate} flipped={flipped} onClose={() => setLooking(null)} />
      </DialogContent>
    </Dialog>
  );
}

/** One card from the customer view, up close: the art, what it is, and the deal price only. */
function CustomerCard({ look, rate, flipped, onClose }: { look: { item: DealItem; incoming: boolean } | null; rate: { in: number; out: number }; flipped: boolean; onClose: () => void }) {
  const i = look?.item;
  const r = look?.incoming ? rate.in : rate.out;
  const each = i ? (unitPrice(i, r) ?? 0) : 0;
  return (
    <Dialog open={!!look} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-[440px]">
        <DialogTitle className="sr-only">{i?.product.name ?? "Card"}</DialogTitle>
        <DialogDescription className="sr-only">The card and its price in this deal.</DialogDescription>
        {i && (
          <div className={cn("min-h-0 flex-1 overflow-y-auto px-6 pb-6 pt-8 text-center", flipped && "rotate-180")}>
            <ProductImage product={i.product} grade={i.grade} size="xl" priority className={cn("mx-auto", i.product.kind === "sealed" ? "aspect-square w-[240px] rounded-3xl" : "aspect-[63/88] w-[230px] rounded-xl")} />
            <h3 className="mt-5 font-display text-[26px] leading-tight tracking-[-0.03em]">{i.product.name}</h3>
            {[i.product.setName, i.product.number && `#${i.product.number}`, i.printing].filter(Boolean).length > 0 && (
              <p className="mt-1 text-[14px] text-muted">{[i.product.setName, i.product.number && `#${i.product.number}`, i.printing].filter(Boolean).join(" · ")}</p>
            )}
            {i.grade && <span className="mt-2 inline-block rounded-full bg-white/10 px-2.5 py-1 font-mono text-[12px] uppercase tracking-[0.08em]">{i.grade.company} {i.grade.grade}</span>}
            <div className="mt-5 rounded-[22px] bg-white/[0.06] py-5 ring-1 ring-inset ring-white/10">
              <p className="font-mono text-[11px] uppercase tracking-[0.1em] text-subtle">{look?.incoming ? "We pay" : "Price"}</p>
              <p className="tabular mt-1 font-display text-[48px] leading-none tracking-[-0.035em]">{money(each * i.qty)}</p>
              {i.qty > 1 && <p className="tabular mt-1.5 text-[14px] text-muted">{i.qty} × {money(each)}</p>}
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

/* ------------------------------ Parked deals ------------------------------ */

/** A notes box that sits on one line until you click into it (or it holds more than a line). */
function NotesField({ value, onChange, placeholder, className, onCommit }: { value: string; onChange: (v: string) => void; placeholder?: string; className?: string; onCommit?: () => void }) {
  const [focused, setFocused] = useState(false);
  const tall = focused || value.includes("\n") || value.length > 60;
  return (
    <textarea
      value={value}
      rows={tall ? 4 : 1}
      placeholder={placeholder}
      aria-label="Notes"
      onFocus={() => setFocused(true)}
      onBlur={() => {
        setFocused(false);
        onCommit?.();
      }}
      onChange={(e) => onChange(e.target.value)}
      className={cn("block w-full resize-none rounded-2xl bg-surface px-3.5 py-2.5 text-[14px] leading-snug outline-none ring-1 ring-inset ring-border placeholder:text-subtle focus:ring-[var(--lime)]/60", className)}
    />
  );
}

/** Name the deal you're setting aside (or keep the time it was parked as its name). */
function ParkDialog({ open, onOpenChange, onPark }: { open: boolean; onOpenChange: (o: boolean) => void; onPark: (name: string) => void }) {
  const [name, setName] = useState("");
  const fallback = parkedDealName(new Date());
  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (!o) setName("");
        onOpenChange(o);
      }}
    >
      <DialogContent className="sm:max-w-[420px]">
        <DialogHeader>
          <DialogTitle>Park this deal</DialogTitle>
          <DialogDescription>Set it aside with its photos and notes, and start a fresh one. Pick it back up from Parked.</DialogDescription>
        </DialogHeader>
        <form
          className="space-y-4 px-6 pb-6 pt-2"
          onSubmit={(e) => {
            e.preventDefault();
            onPark(name);
            setName("");
          }}
        >
          <input autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder={fallback} aria-label="Name" maxLength={80} className="h-11 w-full rounded-full bg-surface-2 px-4 text-[15px] outline-none ring-1 ring-inset ring-border focus:ring-[var(--lime)]/60" />
          <div className="flex gap-2">
            <Button type="button" variant="secondary" size="lg" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" variant="lime" size="lg" className="flex-1">
              Park deal
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Deals set aside: resume one (an open deal is parked first, after asking) or delete it. */
function ParkedDialog({ open, onOpenChange, parked, hasDeal, onResume, onDelete }: { open: boolean; onOpenChange: (o: boolean) => void; parked: ParkedDeal[]; hasDeal: boolean; onResume: (p: ParkedDeal) => void; onDelete: (p: ParkedDeal) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[480px]">
        <DialogHeader className="pt-7">
          <DialogTitle>Parked deals</DialogTitle>
          <DialogDescription>Deals you set aside to finish later, here or in the app.</DialogDescription>
        </DialogHeader>
        <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6 pt-2">
          <ParkedList parked={parked} hasDeal={hasDeal} onResume={onResume} onDelete={onDelete} />
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** The parked deals as rows: a little fan of the cards, name, what and when, delete and Resume. */
function ParkedList({ parked, hasDeal, onResume, onDelete }: { parked: ParkedDeal[]; hasDeal: boolean; onResume: (p: ParkedDeal) => void; onDelete: (p: ParkedDeal) => void }) {
  const [asking, setAsking] = useState<string | null>(null);
  return (
    <ul className="divide-y divide-border">
      {!parked.length && <li className="py-12 text-center text-[14px] text-muted">Nothing parked.</li>}
      {parked.map((p) => {
        const state = { ...EMPTY, ...p.state };
        const items = [...state.in, ...state.out];
        const count = items.reduce((s, i) => s + i.qty, 0);
        const kind = dealKind(state.in.length, state.out.length);
        return (
          <li key={p.id} className="py-3">
            <div className="flex items-center gap-3">
              <div className="flex shrink-0 -space-x-3">
                {items.slice(0, 3).map((i) => (
                  <ProductImage key={i.key} product={i.product} size="xs" className="h-12 w-[34px] rounded-md shadow-lg shadow-black/40" />
                ))}
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate text-[14px] font-semibold">{p.name}</p>
                <p className="truncate text-[12px] text-muted">
                  {KIND_NOUN[kind]} · {count} item{count === 1 ? "" : "s"}
                </p>
                <p className="truncate text-[12px] text-subtle">{new Date(p.savedAt).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}</p>
              </div>
              <Button variant="ghost" size="icon" aria-label={`Delete ${p.name}`} onClick={() => onDelete(p)}>
                <Trash2 />
              </Button>
              <Button variant="lime" onClick={() => (hasDeal ? setAsking(p.id) : onResume(p))}>
                Resume
              </Button>
            </div>
            {asking === p.id && (
              <div className="mt-2 rounded-2xl bg-surface-2 p-3">
                <p className="text-[13px]">You have a deal open. Park it first, then resume this one?</p>
                <div className="mt-2 flex gap-2">
                  <Button variant="secondary" size="sm" onClick={() => setAsking(null)}>
                    Cancel
                  </Button>
                  <Button
                    variant="lime"
                    size="sm"
                    onClick={() => {
                      setAsking(null);
                      onResume(p);
                    }}
                  >
                    Park it and resume
                  </Button>
                </div>
              </div>
            )}
          </li>
        );
      })}
    </ul>
  );
}

/* -------------------------------- History --------------------------------- */

function recordLines(deal: DealState, rate: { in: number; out: number }, tracked: (i: DealItem, side: DealSide) => boolean): DealRecordLine[] {
  const line = (side: DealSide, r: number) => (i: DealItem): DealRecordLine => ({
    side,
    product: { id: i.product.id, name: i.product.name, imageUrl: i.product.imageUrl, kind: i.product.kind, setName: i.product.setName, productType: i.product.productType },
    qty: i.qty,
    price: unitPrice(i, r) ?? 0,
    ...(tracked(i, side) ? {} : { untracked: true }),
  });
  return [...deal.in.map(line("in", rate.in)), ...deal.out.map(line("out", rate.out))];
}

/** The local day a deal closed on, as YYYY-MM-DD. */
const dayOf = (at: string) => new Date(at).toLocaleDateString("en-CA");

/** Closed deals, newest first, grouped by day with each day's totals, with a search and a folded Parked section on top. */
function HistoryDialog({
  open,
  onOpenChange,
  deals,
  onPhotos,
  onNotes,
  parked,
  hasDeal,
  onResume,
  onDelete,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  deals: DealRecord[];
  parked: ParkedDeal[];
  hasDeal: boolean;
  onResume: (p: ParkedDeal) => void;
  onDelete: (p: ParkedDeal) => void;
  onPhotos: (id: string, photos: string[]) => void;
  onNotes: (id: string, notes: string) => void;
}) {
  const [openId, setOpenId] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  // The Parked section starts folded.
  const [parkedOpen, setParkedOpen] = useState(false);
  const today = dayOf(new Date().toISOString());
  const shown = useMemo(() => deals.filter((d) => matchesDealSearch(d, query)), [deals, query]);
  const days = useMemo(() => {
    const map = new Map<string, DealRecord[]>();
    for (const d of shown) {
      const day = dayOf(d.at);
      map.set(day, [...(map.get(day) ?? []), d]);
    }
    return [...map.entries()];
  }, [shown]);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="h-[85dvh] sm:h-[640px] sm:max-w-[560px]">
        <DialogHeader>
          <DialogTitle>Closed deals</DialogTitle>
          <DialogDescription>Every deal you&apos;ve closed here or in the app. The sales and purchases are also in Activity.</DialogDescription>
        </DialogHeader>
        <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-6">
          {deals.length > 0 && (
            <label className="relative mt-1 block">
              <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
              <input type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search cards, notes, buy, sale, trade" aria-label="Search closed deals" className="h-10 w-full rounded-full bg-surface-2 pl-10 pr-4 text-[14px] outline-none ring-1 ring-inset ring-border focus:ring-[var(--lime)]/60" />
            </label>
          )}
          {parked.length > 0 && (
            <section className="mt-3">
              <button type="button" onClick={() => setParkedOpen((o) => !o)} aria-expanded={parkedOpen} className="flex h-12 w-full items-center gap-2.5 rounded-2xl bg-surface-2 px-3.5 text-left ring-1 ring-inset ring-border hover:bg-surface-3">
                <Bookmark className="size-3.5 fill-current text-[var(--lime)]" />
                <span className="text-[15px] font-semibold">Parked</span>
                <span className="tabular text-[14px] text-muted">{parked.length}</span>
                <ChevronDown className={cn("ml-auto size-4 text-muted transition-transform", parkedOpen && "rotate-180")} />
              </button>
              {parkedOpen && <ParkedList parked={parked} hasDeal={hasDeal} onResume={onResume} onDelete={onDelete} />}
            </section>
          )}
          {!deals.length && <p className="py-16 text-center text-[14px] text-muted">No closed deals yet.</p>}
          {deals.length > 0 && !days.length && <p className="py-16 text-center text-[14px] text-muted">No deals match “{query.trim()}”.</p>}
          {days.map(([day, list]) => {
            const t = dealDayTotals(list);
            return (
              <section key={day} className="mt-5">
                <div className="border-b border-border pb-2">
                  <div className="flex items-baseline justify-between gap-3">
                    <h3 className="text-[14px] font-semibold">{day === today ? "Today" : new Date(`${day}T12:00:00`).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric" })}</h3>
                    <span className="text-[12px] text-muted">
                      {t.deals} deal{t.deals === 1 ? "" : "s"}
                    </span>
                  </div>
                  <DayFigures totals={t} className="mt-1" />
                </div>
                <ul className="divide-y divide-border">
                  {list.map((d) => {
                    const expanded = openId === d.id;
                    const ahead = recordAhead(d);
                    return (
                      <li key={d.id}>
                        <button type="button" onClick={() => setOpenId(expanded ? null : d.id)} aria-expanded={expanded} className="flex w-full items-center gap-3 py-3 text-left">
                          <span className="w-16 shrink-0 text-[12px] text-muted">{new Date(d.at).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })}</span>
                          <span className="min-w-0 flex-1">
                            <span className="flex items-center gap-1.5 text-[14px] font-medium">
                              {KIND_NOUN[d.kind]} · {d.items} item{d.items === 1 ? "" : "s"}
                              {d.photos?.length ? (
                                <span className="inline-flex items-center gap-0.5 rounded-full bg-surface-2 px-1.5 text-[11px] text-muted">
                                  <Camera className="size-3" /> {d.photos.length}
                                </span>
                              ) : null}
                            </span>
                            <span className="tabular block text-[12px] text-muted">
                              {Math.abs(d.balance) < 0.005 ? "Even swap" : d.balance > 0 ? `They paid ${money(d.balance)}` : `You paid ${money(-d.balance)}`}
                            </span>
                          </span>
                          <span className="tabular shrink-0 text-right">
                            <span className={cn("block text-[14px] font-semibold", ahead === null ? "text-subtle" : ahead >= 0 ? "text-up" : "text-down")}>{ahead === null ? "—" : signedMoney(ahead)}</span>
                            {d.profit !== null && d.kind !== "buy" ? (
                              <span className="block text-[11px] text-muted">
                                profit <span className={d.profit >= 0 ? "text-up" : "text-down"}>{signedMoney(d.profit)}</span>
                              </span>
                            ) : (
                              <span className="block text-[11px] text-muted">{ahead === null ? "" : ahead < 0 ? "behind" : "ahead"}</span>
                            )}
                          </span>
                          <ChevronDown className={cn("size-4 shrink-0 text-subtle transition-transform", expanded && "rotate-180")} />
                        </button>
                        {expanded && (
                          <div className="pb-3 pl-[4.75rem]">
                            <RecordSummary record={d} ahead={ahead} />
                            {d.lines?.length ? (
                              (["in", "out"] as const).map((side) => {
                                const rows = d.lines!.filter((l) => l.side === side);
                                if (!rows.length) return null;
                                return (
                                  <div key={side} className="mt-1">
                                    <p className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">{side === "in" ? "Came in" : "Went out"}</p>
                                    <ul className="mt-1 space-y-1.5">
                                      {rows.map((l, i) => (
                                        <li key={i} className="flex items-center gap-2.5">
                                          <ProductImage product={l.product} size="xs" className="h-10 w-7 shrink-0 rounded-md" />
                                          <span className="min-w-0 flex-1 truncate text-[13px]">
                                            {l.product.name}
                                            {l.qty > 1 && <span className="text-muted"> × {l.qty}</span>}
                                            {l.untracked && <span className="text-subtle"> · not tracked</span>}
                                          </span>
                                          <span className="tabular shrink-0 text-[13px]">{money(l.price * l.qty)}</span>
                                        </li>
                                      ))}
                                    </ul>
                                  </div>
                                );
                              })
                            ) : (
                              <p className="mt-2 text-[12px] text-muted">Item details weren&apos;t kept for deals closed before they were recorded.</p>
                            )}
                            <p className="mt-3 font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">Notes</p>
                            <RecordNotes notes={d.notes ?? ""} onSave={(next) => onNotes(d.id, next)} />
                            <p className="mt-3 font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">Photos</p>
                            <DealPhotos photos={d.photos ?? []} onChange={(next) => onPhotos(d.id, next)} className="mt-1.5" />
                          </div>
                        )}
                      </li>
                    );
                  })}
                </ul>
              </section>
            );
          })}
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** A day's numbers in one wrapping line: cash in and out, net cash, how far ahead, sale profit. */
function DayFigures({ totals: t, className }: { totals: DealDayTotals; className?: string }) {
  const tone = (n: number) => (n >= 0 ? "text-up" : "text-down");
  const parts: { label: string; value: React.ReactNode }[] = [
    { label: "Cash in", value: money(t.cashIn) },
    { label: "Cash out", value: money(t.cashOut) },
    { label: "Net cash", value: <span className={tone(t.net)}>{signedMoney(t.net)}</span> },
    ...(t.ahead !== null ? [{ label: t.ahead < 0 ? "Behind" : "Ahead", value: <span className={tone(t.ahead)}>{signedMoney(t.ahead)}</span> }] : []),
    ...(t.profit !== null ? [{ label: "Sale profit", value: <span className={tone(t.profit)}>{signedMoney(t.profit)}</span> }] : []),
  ];
  return (
    <p className={cn("tabular flex flex-wrap gap-x-3 gap-y-0.5 text-[12px] text-muted", className)}>
      {parts.map((p) => (
        <span key={p.label}>
          {p.label} <span className="font-semibold text-foreground">{p.value}</span>
        </span>
      ))}
    </p>
  );
}

/** A closed deal's notes, edited in place and saved when you click away. */
function RecordNotes({ notes, onSave }: { notes: string; onSave: (notes: string) => void }) {
  const [text, setText] = useState(notes);
  return (
    <NotesField
      className="mt-1.5"
      value={text}
      onChange={setText}
      placeholder="Add a note"
      onCommit={() => {
        if (text.trim() !== notes.trim()) onSave(text);
      }}
    />
  );
}

/** A closed deal's headline ("You came out ahead +$1,701") over its numbers: what came in and went out, the cash, profit and value gained. */
function RecordSummary({ record: d, ahead }: { record: DealRecord; ahead: number | null }) {
  const cash = Math.abs(d.balance) < 0.005 ? { label: "Cash", value: "Even swap" } : d.balance > 0 ? { label: "They paid you", value: money(d.balance) } : { label: "You paid them", value: money(-d.balance) };
  const equity = d.kind === "sell" ? null : d.equity;
  const stats: { label: string; value: React.ReactNode }[] = [
    { label: "Came in", value: money(d.inValue) },
    { label: "Went out", value: money(d.outValue) },
    cash,
    { label: "Sale profit", value: d.profit === null ? <span className="text-subtle">—</span> : <span className={d.profit >= 0 ? "text-up" : "text-down"}>{signedMoney(d.profit)}</span> },
    { label: "Trade-in value", value: equity === null ? <span className="text-subtle">—</span> : <span className={equity >= 0 ? "text-up" : "text-down"}>{signedMoney(equity)}</span> },
  ];
  return (
    <div className="mb-3">
      {ahead !== null ? (
        <p className="font-display text-[20px] leading-tight tracking-[-0.02em]">
          {aheadTitle(ahead, true)} <span className={cn("tabular", ahead >= 0 ? "text-up" : "text-down")}>{signedMoney(ahead)}</span>
        </p>
      ) : (
        <p className="text-[13px] text-muted">Total unknown: not every item had a cost</p>
      )}
      {ahead !== null && equity !== null && equity > 0.005 && <p className="mt-0.5 text-[12px] text-muted">Includes {money(equity)} on paper</p>}
      <dl className="mt-3 grid grid-cols-3 gap-x-3 gap-y-2.5">
        {stats.map((s) => (
          <div key={s.label} className="min-w-0">
            <dt className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">{s.label}</dt>
            <dd className="tabular mt-0.5 truncate text-[14px] font-semibold">{s.value}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

/**
 * "Profit +$971 · Value gained +$730", with "includes $730 on paper" under it when value was
 * gained. `plain` keeps every figure in the text color (for the lime and pink recorded card).
 */
function AheadBreakdown({ profit, equity, plain, className }: { profit: number | null; equity: number | null; plain?: boolean; className?: string }) {
  const tone = (n: number) => (plain ? "" : n >= 0 ? "text-up" : "text-down");
  const parts = [profit !== null ? { label: "Sale profit", value: profit } : null, equity !== null ? { label: "Trade-in value", value: equity } : null].filter((p): p is { label: string; value: number } => p !== null);
  if (!parts.length) return null;
  return (
    <div className={cn("text-[13px]", className)}>
      <p className={cn("tabular", plain ? "font-semibold" : "text-muted")}>
        {parts.map((p, i) => (
          <span key={p.label}>
            {i > 0 && " · "}
            {p.label} <span className={cn("font-semibold", tone(p.value))}>{signedMoney(p.value)}</span>
          </span>
        ))}
      </p>
      {equity !== null && equity > 0.005 && <p className={cn("mt-0.5 text-[12px]", plain ? "opacity-70" : "text-muted")}>includes {money(equity)} on paper</p>}
    </div>
  );
}

function gradeLabel(g: Grade | null) {
  return g ? `${g.company} ${g.grade}` : "";
}

function sameGrade(a: Grade | null, b: Grade | null) {
  return (!a && !b) || (a?.company === b?.company && a?.grade === b?.grade);
}
