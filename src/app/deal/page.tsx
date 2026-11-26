"use client";

import { ArrowLeftRight, Bookmark, Camera, Check, ChevronLeft, History, MoreHorizontal, Pencil, Plus, ScanLine, SlidersHorizontal, Trash2, Undo2, ArrowUp, Layers } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { DealCard, alpha } from "@/components/deal/deal-card";
import { AmountDialog, ConfirmDialog, DealCardDialog, NameDialog, RateDialog, SettingsDialog } from "@/components/deal/deal-dialogs";
import { ClosedDealsDialog, NotesField, ParkedDialog } from "@/components/deal/deal-history";
import { DealPhotos, deleteDealPhoto } from "@/components/deal/deal-photos";
import { DealPicker, shortName, type DealItem, type DealSide } from "@/components/deal/deal-picker";
import { RecordedDialog, ReviewDialog } from "@/components/deal/deal-review";
import { DealStartPage } from "@/components/deal/deal-start";
import { EMPTY, KIND_COLOR, KIND_NOUN, PATH_TITLE, kindButton, type DealPath, type DealRecord, type DealRecordLine, type DealState, type ParkedDeal } from "@/components/deal/deal-types";
import { ScanSheet, type ScanOutcome, type ScanPick } from "@/components/scan/scan-sheet";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { DEFAULT_RATES, agreedDeal, dealKind, dealTotals, defaultSideRates, lineShare, marketAgreed, marketOf, renegotiates, roundStep, roundedCash, signedAgreedCash, unitPrice, parkedDealName, unroundedDeal, withAgreedCash, withAgreedMarket, withCatalogMarket, type DealRates, type DealTotals } from "@/lib/deal";
import { fifoCost } from "@/lib/finance/sell";
import { money, signedMoney } from "@/lib/format";
import { scanValue } from "@/lib/scan-types";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useSyncedState } from "@/lib/store/synced-state";
import type { Condition, Grade } from "@/lib/types";
import { cn } from "@/lib/utils";

/** A value kept in this browser only (the app keeps the deal's kind and name on the phone). */
function useLocalValue(key: string): [string, (v: string) => void] {
  const [value, setValue] = useState("");
  useEffect(() => {
    try {
      setValue(localStorage.getItem(key) ?? "");
    } catch {
      /* storage blocked: start fresh */
    }
  }, [key]);
  const set = useCallback(
    (v: string) => {
      setValue(v);
      try {
        if (v) localStorage.setItem(key, v);
        else localStorage.removeItem(key);
      } catch {
        /* storage blocked: keep it for this visit */
      }
    },
    [key],
  );
  return [value, set];
}

const isPath = (v: string): v is DealPath => v === "buy" || v === "sell" || v === "trade";

/**
 * Deal maker for card shows, the same as the app (Nov 2026): a start page that asks what you're
 * doing (buy, sell or trade, always from your side), then one page per deal: the deal card with
 * the rate for all cards, Scan / Add cards, the cards (click one to change its rate, price or
 * quantity), and Save for later / Review deal pinned at the bottom.
 */
export default function DealPage() {
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const { addTransaction, importProduct, today, data, mode } = useStore();
  const [stored, setStored] = useSyncedState<DealState>("deal", EMPTY);
  /**
   * Every edit to the open deal goes through here. One that renegotiates it (a side's %, a line's
   * % or price or quantity, a line added or removed) lets go of an agreed cash figure.
   */
  const setDeal = (next: DealState | ((cur: DealState) => DealState)) =>
    setStored((cur) => {
      const before = { ...EMPTY, ...cur };
      const after = typeof next === "function" ? next(before) : next;
      const agreed = after.agreedCash ?? null;
      if (agreed === null || agreed !== (before.agreedCash ?? null) || !renegotiates(before, after)) return after;
      return { ...after, agreedCash: undefined };
    });
  const deal = { ...EMPTY, ...stored };
  const photos = deal.photos ?? [];
  const [ratesStored, setRates] = useSyncedState<DealRates>("deal-rates", DEFAULT_RATES);
  const rates = { ...DEFAULT_RATES, ...ratesStored };
  const [log, setLog] = useSyncedState<DealRecord[]>("deals", []);
  const [parkedStored, setParked] = useSyncedState<ParkedDeal[]>("deals-parked", []);
  const parked = parkedStored ?? [];
  const [pathRaw, setPathRaw] = useLocalValue("deal-path");
  const [dealName, setDealName] = useLocalValue("deal-name");

  const [picking, setPicking] = useState<DealSide | null>(null);
  const [scanning, setScanning] = useState<DealSide | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [historyId, setHistoryId] = useState<string | null>(null);
  const [parkedOpen, setParkedOpen] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [closing, setClosing] = useState(false);
  const [recorded, setRecorded] = useState<{ record: DealRecord; totals: DealTotals; deal: DealState } | null>(null);
  const [tradeSide, setTradeSide] = useState<DealSide>("in");
  const [editing, setEditing] = useState<DealItem | null>(null);
  const [rateOpen, setRateOpen] = useState(false);
  const [cashOpen, setCashOpen] = useState(false);
  const [marketOpen, setMarketOpen] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const [confirmKind, setConfirmKind] = useState<DealPath | null>(null);
  const [extrasOpen, setExtrasOpen] = useState(false);

  const byKey = useMemo(() => new Map(holdings.map((h) => [h.key, h])), [holdings]);
  const kind = dealKind(deal.in.length, deal.out.length);
  /** The kind picked when the deal started, else what its cards say (null: the start page asks). */
  const path: DealPath | null = isPath(pathRaw) ? pathRaw : kind === "empty" ? null : kind;
  const ratesFor = (d: DealState) => {
    const def = defaultSideRates(dealKind(d.in.length, d.out.length), rates);
    return { in: d.rateIn ?? def.in, out: d.rateOut ?? def.out };
  };
  const rate = ratesFor(deal);

  // A deal that had cards and is now empty (closed, saved or cleared): next time, ask again.
  const wasEmpty = useRef(true);
  useEffect(() => {
    const empty = kind === "empty";
    if (empty && !wasEmpty.current) {
      setPathRaw("");
      setDealName("");
    }
    wasEmpty.current = empty;
  }, [kind, setPathRaw, setDealName]);

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
  const totalsOf = (d: DealState, r: { in: number; out: number }) =>
    dealTotals(
      d.in.map((i) => ({ market: i.market, qty: i.qty, price: i.price, rate: i.rate })),
      d.out.map((i) => ({ market: i.market, qty: i.qty, price: i.price, rate: i.rate, cost: costOf(i) })),
      r,
    );
  // The deal at its agreed cash, when one is set (the stored prices never change).
  const agreed = agreedDeal(deal.in, deal.out, rate, kind === "empty" ? null : deal.agreedCash);
  const settled: DealState = { ...deal, in: agreed.incoming, out: agreed.outgoing };
  const isAgreed = agreed.side !== null;
  const totals = totalsOf(settled, rate);
  // The cards on their own (no rounding, whole %s): what Round up rounds and Reset goes back to.
  const plain = unroundedDeal(deal);
  const plainTotals = totalsOf(plain, ratesFor(plain));
  const unpriced = [...deal.in.map((i) => unitPrice(i, rate.in)), ...deal.out.map((i) => unitPrice(i, rate.out))].some((p) => p === null);

  // Updates build on the latest deal, so rapid scans landing back to back all count.
  const add = (side: DealSide, item: DealItem) =>
    setDeal((cur) => {
      const d = { ...EMPTY, ...cur };
      const existing = d[side].find((i) => i.key === item.key);
      const items = existing ? d[side].map((i) => (i.key === item.key ? { ...i, qty: Math.min(i.qty + 1, i.maxQty ?? Infinity) } : i)) : [...d[side], item];
      return { ...d, [side]: items };
    });
  const removeKey = (key: string) => setDeal((cur) => ({ ...EMPTY, ...cur, in: cur.in.filter((i) => i.key !== key), out: cur.out.filter((i) => i.key !== key) }));
  const replace = (changed: DealItem) => setDeal((cur) => ({ ...EMPTY, ...cur, in: cur.in.map((i) => (i.key === changed.key ? changed : i)), out: cur.out.map((i) => (i.key === changed.key ? changed : i)) }));
  const setPhotos = (next: string[]) => setDeal((cur) => ({ ...EMPTY, ...cur, photos: next }));

  /** A scanned card: anything can come in; going out, one you don't hold is added as not in Corodex. */
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
      return { ok: true, note: "Added · not in Corodex" };
    }
    add("out", { key: `h:${h.key}`, product: h.product!, printing: h.identity.printing, market: h.price, qty: 1, price: null, holdingKey: h.key, maxQty: h.quantity });
    return { ok: true, note: "Added to going out" };
  };

  /**
   * Settle on a cash amount (signed like the balance): the moving side's % goes to what gets there
   * and the agreed cash lands it to the cent (withAgreedCash). Straight in, not through setDeal,
   * which would read the % moving as a renegotiation and let it go again.
   */
  const agreeCash = (cash: number) =>
    setStored((cur) => {
      const d = { ...EMPTY, ...cur };
      if (!d.in.length && !d.out.length) return d;
      return withAgreedCash(d, ratesFor(d), cash);
    });
  const roundTo = kind === "empty" ? null : roundedCash(plainTotals.balance, roundStep(rates));
  /** Back to the cards' own total, each side's % on a whole number again. */
  const clearAgreedTotal = () => setStored((cur) => unroundedDeal({ ...EMPTY, ...cur }));

  const hasDeal = kind !== "empty" || photos.length > 0 || Boolean(deal.notes?.trim());
  const parkEntry = (state: DealState, name: string): ParkedDeal => ({ id: crypto.randomUUID(), name: name.trim() || parkedDealName(new Date()), savedAt: new Date().toISOString(), state: { ...EMPTY, ...state } });
  /** Set the open deal aside under its name (photos and notes go with it) and go back to the start. */
  const parkNow = () => {
    if (!hasDeal) return;
    const entry = parkEntry(deal, dealName);
    setParked((cur) => [entry, ...(cur ?? [])]);
    setDeal(EMPTY);
    setPathRaw("");
    setDealName("");
    toast(`Saved “${entry.name}” for later`);
  };
  /** Pick a saved deal back up; an open one is saved first. */
  const resume = (p: ParkedDeal) => {
    const current = hasDeal ? parkEntry(deal, dealName) : null;
    setParked((cur) => [...(current ? [current] : []), ...(cur ?? []).filter((x) => x.id !== p.id)]);
    // Straight in, agreed cash and all (not through setDeal, which would read it as a renegotiation).
    const state = { ...EMPTY, ...p.state };
    setStored(state);
    const k = dealKind(state.in.length, state.out.length);
    setPathRaw(k === "empty" ? "" : k);
    setDealName(p.name);
    setParkedOpen(false);
    toast(current ? `Saved the open deal for later and resumed “${p.name}”` : `Resumed “${p.name}”`);
  };
  const deleteParked = (p: ParkedDeal) => {
    for (const ph of p.state.photos ?? []) void deleteDealPhoto(ph);
    setParked((cur) => (cur ?? []).filter((x) => x.id !== p.id));
  };
  /** Throws the open deal away (its photos too) and goes back to the start. */
  const discardDeal = () => {
    for (const ph of photos) void deleteDealPhoto(ph);
    setDeal(EMPTY);
    setPathRaw("");
    setDealName("");
  };
  /** A deal type from the ⋯ menu: dropping a side with cards asks first. */
  const pickKind = (k: DealPath) => {
    const dropping = k === "buy" ? deal.out : k === "sell" ? deal.in : [];
    if (path === k || !dropping.length) setPathRaw(k);
    else setConfirmKind(k);
  };
  const switchDropping = (k: DealPath) => {
    setPathRaw(k);
    setDeal((cur) => ({ ...EMPTY, ...cur, [k === "buy" ? "out" : "in"]: [] }));
  };
  const effects = {
    adds: settled.in.filter((i) => tracked(i, "in")).reduce((s, i) => s + i.qty, 0),
    sells: settled.out.filter((i) => tracked(i, "out")).reduce((s, i) => s + i.qty, 0),
    untracked: [...settled.in.filter((i) => !tracked(i, "in")), ...settled.out.filter((i) => !tracked(i, "out"))].reduce((s, i) => s + i.qty, 0),
  };

  const close = async () => {
    if (unpriced || kind === "empty") return;
    setClosing(true);
    const note = `Show deal (${KIND_NOUN[kind].toLowerCase()})`;
    try {
      // At the agreed cash, when there is one: the record's prices add up to it.
      for (const item of settled.out) {
        const unit = unitPrice(item, rate.out)!;
        const h = item.holdingKey ? byKey.get(item.holdingKey) : undefined;
        if (h) {
          await addTransaction({ ...h.identity, type: "sale", date: today, quantity: item.qty, unitPrice: unit, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: note });
        } else if (!item.custom && item.cost !== null && item.cost !== undefined) {
          // Not in Corodex, but you said what you paid: record that purchase, then the sale.
          if (!data.products[item.product.id]) await importProduct(item.product.id, item.printing ?? null, item.product.kind);
          const identity = { productId: item.product.id, printing: item.printing ?? null, condition: (item.product.kind === "sealed" ? "Sealed" : "Near Mint") as Condition, grade: item.grade ?? null };
          await addTransaction({ ...identity, type: "purchase", date: today, quantity: item.qty, unitPrice: item.cost, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: "Added from a deal" });
          await addTransaction({ ...identity, type: "sale", date: today, quantity: item.qty, unitPrice: unit, fees: 0, shipping: 0, tax: 0, source: "Card show", notes: note });
        }
      }
      for (const item of settled.in) {
        if (!tracked(item, "in")) continue;
        const h = item.holdingKey ? byKey.get(item.holdingKey) : undefined;
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
        lines: recordLines(settled, rate, tracked),
        photos: photos.length ? photos : undefined,
        notes: deal.notes?.trim() || undefined,
      };
      setLog((cur) => [record, ...cur].slice(0, 500));
      setRecorded({ record, totals, deal: settled });
      setReviewing(false);
      setDeal(EMPTY);
    } catch (err) {
      toast.error("Couldn't record the deal", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setClosing(false);
    }
  };

  const parkedBalance = (p: ParkedDeal) => {
    const s = { ...EMPTY, ...p.state };
    const r = ratesFor(s);
    const a = agreedDeal(s.in, s.out, r, s.agreedCash);
    return dealTotals(a.incoming, a.outgoing, r).balance;
  };

  const shared = (
    <>
      <SettingsDialog open={settingsOpen} onOpenChange={setSettingsOpen} rates={rates} onSave={setRates} />
      <ClosedDealsDialog
        open={historyOpen}
        onOpenChange={(o) => {
          setHistoryOpen(o);
          if (!o) setHistoryId(null);
        }}
        deals={log}
        openId={historyId}
        onOpenId={setHistoryId}
        onPhotos={(id, next) => setLog((cur) => cur.map((d) => (d.id === id ? { ...d, photos: next.length ? next : undefined } : d)))}
        onNotes={(id, next) => setLog((cur) => cur.map((d) => (d.id === id ? { ...d, notes: next.trim() || undefined } : d)))}
      />
      <ParkedDialog open={parkedOpen} onOpenChange={setParkedOpen} parked={parked} balanceOf={parkedBalance} onResume={resume} onDelete={deleteParked} />
      <RecordedDialog recorded={recorded} onDone={() => setRecorded(null)} />
    </>
  );

  if (!path) {
    return (
      <div className="animate-fade-in pb-28 lg:pb-8">
        <PageHeader
          title="Deal"
          actions={
            <div className="flex gap-1">
              <Button variant="ghost" size="icon" aria-label="Closed deals" onClick={() => setHistoryOpen(true)}>
                <History />
              </Button>
              <Button variant="ghost" size="icon" aria-label="Deal settings" onClick={() => setSettingsOpen(true)}>
                <SlidersHorizontal />
              </Button>
            </div>
          }
        />
        <DealStartPage
          parked={parked}
          log={log}
          parkedBalance={parkedBalance}
          onPick={(k) => {
            setPathRaw(k);
            setTradeSide("in");
          }}
          onResume={resume}
          onDeleteParked={deleteParked}
          onParkedAll={() => setParkedOpen(true)}
          onHistory={() => setHistoryOpen(true)}
          onRecord={(r) => {
            setHistoryId(r.id);
            setHistoryOpen(true);
          }}
        />
        {shared}
      </div>
    );
  }

  // ------------------------------- The deal -------------------------------
  const side: DealSide = path === "buy" ? "in" : path === "sell" ? "out" : tradeSide;
  const color = KIND_COLOR[path];
  const items = deal[side];
  const settledBy = new Map(settled[side].map((i) => [i.key, i]));
  const sideRate = side === "in" ? rate.in : rate.out;
  const pct = Math.round(sideRate * 100);
  const count = deal.in.length + deal.out.length;
  const rateTitle = path === "buy" ? "Buying rate" : path === "sell" ? "Selling rate" : side === "in" ? "Coming in rate" : "Going out rate";
  const marketSide: DealSide | null = kind === "buy" ? "in" : kind === "sell" ? "out" : null;
  const setSideRate = (r: number) => setDeal((cur) => ({ ...EMPTY, ...cur, [side === "in" ? "rateIn" : "rateOut"]: r }));
  const roundedDelta = isAgreed ? Math.abs(totals.balance) - Math.abs(plainTotals.balance) : null;
  const editingIncoming = editing ? deal.in.some((i) => i.key === editing.key) : false;

  const rateSection = (
    <div className="mt-[18px] space-y-2.5">
      <div className="flex items-center gap-2.5">
        <div className="min-w-0 flex-1">
          <p className="text-[15px] font-semibold">{rateTitle}</p>
          <p className="text-[12px] text-white/65">Default for all cards</p>
        </div>
        <span className="tabular font-display text-[26px] leading-none tracking-[-0.03em]">{pct}%</span>
        {kind !== "empty" &&
          (deal.agreedCash !== null && deal.agreedCash !== undefined ? (
            <CardChip onClick={clearAgreedTotal} icon={<Undo2 className="size-3" />}>
              Undo round
            </CardChip>
          ) : (
            roundTo !== null && (
              <CardChip onClick={() => agreeCash(signedAgreedCash(Math.abs(roundTo), plainTotals))} icon={<ArrowUp className="size-3" />} label={`Round up to ${money(Math.abs(roundTo))}`}>
                Round up
              </CardChip>
            )
          ))}
      </div>
      <div className="grid grid-cols-6 gap-1.5">
        {[75, 80, 85, 90, 100].map((v) => (
          <button key={v} type="button" aria-pressed={v === pct} onClick={() => setSideRate(v / 100)} className={cn("tabular h-9 rounded-[13px] text-[13px] font-semibold transition-colors", v === pct ? "bg-white text-[#0b0b0c]" : "bg-[rgb(11_11_12/0.35)] text-white hover:bg-[rgb(11_11_12/0.5)]")}>
            {v}%
          </button>
        ))}
        <button type="button" aria-label="Another rate" onClick={() => setRateOpen(true)} className="flex h-9 items-center justify-center rounded-[13px] bg-[rgb(11_11_12/0.35)] text-white hover:bg-[rgb(11_11_12/0.5)]">
          <MoreHorizontal className="size-4" />
        </button>
      </div>
    </div>
  );

  return (
    <div className="relative animate-fade-in pb-64 lg:pb-8">
      {/* The page glows in its kind's colour (blue buy, lime sell, purple trade). */}
      <div aria-hidden className="pointer-events-none absolute -inset-x-4 -top-10 -z-10 h-[420px] sm:-inset-x-8" style={{ background: `radial-gradient(60% 55% at 20% 0%, ${alpha(color.tint, 0.22)}, transparent 70%), radial-gradient(45% 45% at 90% 10%, ${alpha(path === "trade" ? KIND_COLOR.buy.tint : color.tint, 0.14)}, transparent 70%)` }} />
      <div className="mx-auto max-w-[640px]">
        {/* The bar: leave (save or discard), the kind, settings. */}
        <div className="flex items-center justify-between">
          <button type="button" onClick={() => (hasDeal ? setLeaving(true) : setPathRaw(""))} aria-label="Leave this deal" className="-ml-2 flex size-10 items-center justify-center rounded-full text-foreground hover:bg-white/[0.06]">
            <ChevronLeft className="size-5" />
          </button>
          <p className="text-[16px] font-semibold">{PATH_TITLE[path]} cards</p>
          <button type="button" onClick={() => setSettingsOpen(true)} aria-label="Deal settings" className="-mr-2 flex size-10 items-center justify-center rounded-full text-foreground hover:bg-white/[0.06]">
            <SlidersHorizontal className="size-[18px]" />
          </button>
        </div>

        <div className="mt-2 space-y-[18px]">
          <div className="flex items-start gap-3">
            <div className="min-w-0 flex-1">
              <h1 className="font-display text-[30px] leading-none tracking-[-0.03em]">{path === "buy" ? "New purchase" : path === "sell" ? "New sale" : "New trade"}</h1>
              <p className="mt-1.5 text-[14px] text-muted">
                {dealName || "Untitled deal"} · {count} card{count === 1 ? "" : "s"}
              </p>
            </div>
            <DropdownMenu>
              <DropdownMenuTrigger aria-label="Deal actions" className="glass-stat flex size-10 shrink-0 items-center justify-center rounded-full hover:bg-white/[0.1]">
                <MoreHorizontal className="size-[18px]" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-[220px]">
                <DropdownMenuItem onSelect={() => setRenaming(true)}>
                  <Pencil className="size-4" /> {dealName ? "Rename deal" : "Name deal"}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuLabel>Change deal type</DropdownMenuLabel>
                {(["buy", "sell", "trade"] as const).map((k) => (
                  <DropdownMenuItem key={k} onSelect={() => pickKind(k)}>
                    <span className="flex size-4 items-center justify-center">{path === k && <Check className="size-4" />}</span> {PATH_TITLE[k]}
                  </DropdownMenuItem>
                ))}
                {hasDeal && (
                  <>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem onSelect={parkNow}>
                      <Bookmark className="size-4" /> Save for later
                    </DropdownMenuItem>
                  </>
                )}
                <DropdownMenuSeparator />
                <DropdownMenuItem onSelect={discardDeal} className="text-[var(--plan-pink)] focus:text-[var(--plan-pink)]">
                  <Trash2 className="size-4" /> Delete deal
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>

          {path === "trade" && (
            <div className="grid grid-cols-2 gap-2">
              {(["in", "out"] as const).map((s) => (
                <button key={s} type="button" aria-pressed={tradeSide === s} onClick={() => setTradeSide(s)} className={cn("tabular h-10 truncate rounded-[13px] px-3 text-[14px] font-semibold transition-colors", tradeSide === s ? "bg-white text-[#0b0b0c]" : "glass-stat text-white hover:bg-white/[0.08]")}>
                  {s === "in" ? "Coming in" : "Going out"} · {money(s === "in" ? totals.inValue : totals.outValue)}
                </button>
              ))}
            </div>
          )}

          <DealCard
            totals={totals}
            tagKind={path}
            agreed={isAgreed}
            onEditCash={() => setCashOpen(true)}
            rounded={roundedDelta !== null ? { delta: roundedDelta, onReset: clearAgreedTotal } : null}
            extra={rateSection}
            onEditMarket={marketSide ? () => setMarketOpen(true) : null}
            marketAgreed={marketSide ? marketAgreed(deal[marketSide]) : false}
          />

          <div className="flex gap-2.5">
            <button type="button" onClick={() => setScanning(side)} className="glass-stat flex h-12 flex-1 items-center justify-center gap-2 rounded-full text-[15px] font-semibold hover:bg-white/[0.08] lg:hidden">
              <ScanLine className="size-4" /> Scan card
            </button>
            <button type="button" onClick={() => setPicking(side)} className="flex h-12 flex-1 items-center justify-center gap-2 rounded-full text-[15px] font-semibold transition-[filter] hover:brightness-105" style={kindButton(path)}>
              <Plus className="size-4" /> Add cards
            </button>
          </div>

          {/* The cards on this side; click one for its price. */}
          <section>
            <div className="flex items-baseline gap-2 pt-2">
              <h2 className="font-display text-[20px] tracking-[-0.02em]">{path === "trade" ? (side === "in" ? "Coming in" : "Going out") : "Cards"}</h2>
              <span className="text-[14px] text-subtle">{items.reduce((s, i) => s + i.qty, 0)}</span>
              <span className="tabular ml-auto text-[13px] text-muted">{money(marketOf(items))} market</span>
            </div>
            {!items.length ? (
              <div className="flex flex-col items-center gap-2 py-9 text-center">
                <Layers className="size-[22px] text-subtle" />
                <p className="text-[14px] font-medium text-muted">No cards added yet.</p>
                <p className="text-[13px] text-subtle">Scan or search to start your deal.</p>
              </div>
            ) : (
              <ul className="mt-1">
                {items.map((item, i) => {
                  const shown = settledBy.get(item.key) ?? item;
                  const unit = unitPrice(shown, sideRate);
                  const total = unit === null ? null : unit * item.qty;
                  const selling = side === "out";
                  const cost = selling ? costOf(item) : null;
                  const profit = cost !== null && total !== null ? total - cost : null;
                  const share = lineShare(unit, item.market);
                  const own = item.price !== null || (item.rate !== null && item.rate !== undefined) || Boolean(share?.offWhole);
                  return (
                    <li key={item.key} className={cn(i > 0 && "border-t border-border")}>
                      <button type="button" onClick={() => setEditing(item)} className="flex w-full items-center gap-3 py-2.5 text-left">
                        <ProductImage product={item.product} size="sm" className="h-[89px] w-16 shrink-0 rounded-[4px]" />
                        <span className="min-w-0 flex-1 space-y-0.5">
                          <span className="block truncate text-[15px] font-medium">{shortName(item.product)}</span>
                          <span className="block truncate text-[12px] text-muted">{[item.product.setName, item.product.number].filter(Boolean).join(" · ") || (item.custom ? "Custom item" : "")}</span>
                          <span className="tabular block truncate text-[12px] text-subtle">
                            {item.qty > 1 ? `×${item.qty} · ` : ""}
                            {item.market !== null ? `${money(item.market)} market` : "No market price"}
                            {item.catalogMarket !== null && item.catalogMarket !== undefined ? ` (was ${money(item.catalogMarket)})` : ""}
                          </span>
                          {selling && !item.custom && (cost !== null ? <span className="tabular block text-[12px] text-muted">Paid {money(cost)}</span> : <span className="block text-[12px] font-medium" style={{ color: color.tint }}>Add what you paid</span>)}
                        </span>
                        <span className="flex shrink-0 flex-col items-end gap-1">
                          <span className="tabular text-[15px] font-semibold" style={total === null ? { color: color.tint } : undefined}>
                            {total === null ? "Set price" : money(total)}
                          </span>
                          {share && (
                            <span className="tabular inline-flex h-5 items-center gap-0.5 rounded-full bg-white/[0.08] px-[7px] text-[11px] font-semibold text-white/80">
                              {share.label}%{own && <Pencil className="size-2" strokeWidth={3} />}
                            </span>
                          )}
                          {profit !== null && <span className={cn("tabular text-[12px] font-semibold", profit >= 0 ? "text-up" : "text-down")}>{signedMoney(profit)}</span>}
                        </span>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
            {/* A buy or a sale that turns out to go both ways. */}
            {path !== "trade" && items.length > 0 && (
              <button
                type="button"
                onClick={() => {
                  const other: DealSide = path === "buy" ? "out" : "in";
                  setPathRaw("trade");
                  setTradeSide(other);
                  setPicking(other);
                }}
                className="flex w-full items-center gap-1.5 py-2 text-left text-[14px] font-medium"
                style={{ color: KIND_COLOR.trade.tint }}
              >
                <ArrowLeftRight className="size-3.5" strokeWidth={2.5} />
                <span className="text-muted">{path === "buy" ? "Also selling cards?" : "Also buying cards?"}</span> Make it a trade
              </button>
            )}
          </section>

          {/* Photos and notes, one quiet row until wanted. */}
          {extrasOpen || photos.length > 0 || deal.notes ? (
            <div className="space-y-6 pt-2">
              <section>
                <h2 className="flex items-baseline gap-2 font-display text-[20px] tracking-[-0.02em]">
                  Photos {photos.length > 0 && <span className="font-mono text-[12px] text-subtle">{photos.length}</span>}
                </h2>
                <p className="mt-1 text-[12px] text-muted">The cards on the table, a receipt, their binder</p>
                <DealPhotos photos={photos} onChange={setPhotos} className="mt-3" />
              </section>
              <section>
                <h2 className="font-display text-[20px] tracking-[-0.02em]">Notes</h2>
                <NotesField className="mt-3" value={deal.notes ?? ""} onChange={(v) => setDeal((cur) => ({ ...EMPTY, ...cur, notes: v || undefined }))} placeholder="Who it was with, how they paid, anything to remember" />
              </section>
            </div>
          ) : (
            <button type="button" onClick={() => setExtrasOpen(true)} className="glass-stat flex h-[50px] w-full items-center gap-2.5 rounded-2xl px-4 text-[15px] font-medium text-muted hover:text-foreground">
              <Camera className="size-4" /> Add a photo or note
            </button>
          )}
        </div>
      </div>

      {/* Pinned at the bottom: just Save for later and Review deal (the deal card above says the amounts). */}
      <div className="fixed inset-x-0 bottom-[calc(4.5rem+env(safe-area-inset-bottom))] z-30 px-4 lg:sticky lg:bottom-4 lg:mt-6 lg:px-0">
        <div className="mx-auto max-w-[640px] rounded-[22px] border border-border bg-[#0b0b0c]/90 p-3 shadow-2xl shadow-black/60 backdrop-blur-xl">
          <div className="flex gap-2.5">
            <button type="button" onClick={parkNow} disabled={!hasDeal} aria-label="Save for later" className="glass-stat flex size-[52px] shrink-0 items-center justify-center rounded-2xl hover:bg-white/[0.08] disabled:opacity-50">
              <Bookmark className="size-4" />
            </button>
            <button type="button" onClick={() => setReviewing(true)} disabled={kind === "empty" || unpriced} className="h-[52px] flex-1 rounded-2xl text-[16px] font-semibold disabled:opacity-45" style={kindButton(path)}>
              {unpriced ? "Price every card to review" : "Review deal"}
            </button>
          </div>
        </div>
      </div>

      <DealPicker side={picking} onDeal={new Set((picking ? deal[picking] : []).map((i) => i.key))} onClose={() => setPicking(null)} onPick={(item) => picking && add(picking, item)} onRemove={removeKey} />
      <ScanSheet
        open={scanning !== null}
        onOpenChange={(o) => !o && setScanning(null)}
        title={scanning === "out" ? "Scan going out" : "Scan coming in"}
        description={scanning === "out" ? "Each card you scan joins the deal; ones not in Corodex are marked so." : "Each card you scan joins the deal at the current rate."}
        onPick={(pick) => addScan(scanning ?? "in", pick)}
      />
      <DealCardDialog item={editing} rate={editingIncoming ? rate.in : rate.out} selling={!editingIncoming} collectionCost={editing?.holdingKey ? costOf(editing) : null} onSave={replace} onRemove={(i) => removeKey(i.key)} onClose={() => setEditing(null)} />
      <RateDialog open={rateOpen} onOpenChange={setRateOpen} rate={sideRate} onApply={setSideRate} />
      <AmountDialog
        open={cashOpen}
        onOpenChange={setCashOpen}
        title="Agreed cash"
        line={`${signedAgreedCash(1, totals) > 0 ? "What they pay you." : "What you pay them."} The prices ${deal.out.length ? "going out" : "coming in"} move to match.`}
        initial={Math.abs(totals.balance)}
        submit="Set cash"
        onSet={(n) => agreeCash(signedAgreedCash(n, totals))}
      />
      <AmountDialog
        open={marketOpen}
        onOpenChange={setMarketOpen}
        title="Agreed market value"
        line="What the cards are worth, as you both agreed. Cards priced at a % of market follow it."
        initial={(marketSide === "in" ? totals.inMarket : totals.outMarket) ?? 0}
        submit="Set"
        onSet={(n) => marketSide && setDeal((cur) => ({ ...EMPTY, ...cur, [marketSide]: withAgreedMarket(cur[marketSide], n), agreedCash: undefined }))}
        secondary={marketSide && marketAgreed(deal[marketSide]) ? { label: "Back to catalog prices", onClick: () => setDeal((cur) => ({ ...EMPTY, ...cur, [marketSide]: withCatalogMarket(cur[marketSide]), agreedCash: undefined })) } : null}
      />
      <NameDialog open={renaming} onOpenChange={setRenaming} title="Name this deal" initial={dealName} submit="Save" onSave={setDealName} />
      <ConfirmDialog
        open={leaving}
        onOpenChange={setLeaving}
        title="Leave this deal?"
        actions={[
          { label: "Save for later", onClick: parkNow },
          { label: "Discard deal", onClick: discardDeal, danger: true },
        ]}
      />
      <ConfirmDialog
        open={confirmKind !== null}
        onOpenChange={(o) => !o && setConfirmKind(null)}
        title={confirmKind ? dropTitle(confirmKind, deal) : ""}
        line={confirmKind ? `This deal becomes ${PATH_TITLE[confirmKind].toLowerCase()} only.` : undefined}
        actions={[{ label: "Remove and switch", onClick: () => confirmKind && switchDropping(confirmKind), danger: true }]}
      />
      <ReviewDialog open={reviewing} onOpenChange={setReviewing} path={path} totals={totals} deal={settled} effects={effects} agreed={isAgreed} closing={closing} demo={mode === "demo"} onClose={() => void close()} />
      {shared}
    </div>
  );
}

/** A quiet outlined chip on the deal card (Round up, Undo round). */
function CardChip({ onClick, icon, label, children }: { onClick: () => void; icon: React.ReactNode; label?: string; children: React.ReactNode }) {
  return (
    <button type="button" onClick={onClick} aria-label={label} className="inline-flex h-[34px] shrink-0 items-center gap-1.5 rounded-full bg-[rgb(11_11_12/0.35)] px-3 text-[13px] font-semibold text-white ring-1 ring-inset ring-white/25 hover:bg-[rgb(11_11_12/0.5)]">
      {icon} {children}
    </button>
  );
}

/** "Remove the 2 cards you're selling?" */
function dropTitle(k: DealPath, deal: DealState) {
  const dropping = k === "buy" ? deal.out : deal.in;
  const n = dropping.reduce((s, i) => s + i.qty, 0);
  return `Remove the ${n} card${n === 1 ? "" : "s"} you're ${k === "buy" ? "selling" : "buying"}?`;
}

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

function gradeLabel(g: Grade | null) {
  return g ? `${g.company} ${g.grade}` : "";
}

function sameGrade(a: Grade | null, b: Grade | null) {
  return (!a && !b) || (a?.company === b?.company && a?.grade === b?.grade);
}

