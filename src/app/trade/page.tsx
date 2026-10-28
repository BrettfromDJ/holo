"use client";

import { ArrowLeftRight, Loader2, Minus, Plus, Search, Trash2 } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Segmented } from "@/components/ui/segmented";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { ExploreProduct } from "@/lib/explore/types";
import { money, pct } from "@/lib/format";
import { usePortfolio } from "@/lib/store/collection-store";
import { useSyncedState } from "@/lib/store/synced-state";
import type { Product } from "@/lib/types";
import { cn } from "@/lib/utils";

interface TradeItem {
  key: string;
  product: Product;
  /** Value per unit: the latest saved market price, unless typed in. */
  unit: number | null;
  qty: number;
  /** Units you own, for items picked from your collection. */
  maxQty?: number;
  /** Printing the catalog price is for. */
  printing?: string | null;
  /** True once the value was typed in; those are never refreshed. */
  custom?: boolean;
}

type Side = "give" | "get";
interface TradeState {
  give: TradeItem[];
  get: TradeItem[];
  /** Share of market value each side is counted at (e.g. 0.9 for trade-in value). */
  rate: Record<Side, number>;
}

const KEY = "holo:trade:v1";
const EMPTY: TradeState = { give: [], get: [], rate: { give: 1, get: 1 } };
const RATES = [1, 0.95, 0.9, 0.85, 0.8, 0.7];
/** Within this share of the larger side, a trade counts as even. */
const FAIR = 0.05;

function sideValue(items: TradeItem[], rate: number) {
  return items.reduce((s, i) => s + (i.unit ?? 0) * i.qty, 0) * rate;
}

/** Latest saved market price for a catalog product (no TCG API requests). */
async function latestCatalogPrice(item: TradeItem): Promise<number | null | undefined> {
  const res = await fetch(`/api/explore/products/${encodeURIComponent(item.product.id)}`);
  if (!res.ok) return undefined;
  const { prices } = (await res.json()) as { prices: { printing: string | null; market: number | null }[] };
  const match = prices.find((p) => p.printing === (item.printing ?? null) && p.market !== null) ?? prices.find((p) => p.market !== null);
  return match ? match.market : undefined;
}

export default function TradePage() {
  // The trade in progress follows you across devices when signed in.
  const [stored, setStored, ready] = useSyncedState<TradeState>("trade", EMPTY, { legacyKey: KEY });
  const trade: TradeState = { ...EMPTY, ...stored };
  const [picking, setPicking] = useState<Side | null>(null);
  const { holdings } = usePortfolio({ ignoreFilter: true });

  // Each visit, refresh every value that wasn't typed in to the latest saved price.
  const [refreshed, setRefreshed] = useState(false);
  useEffect(() => {
    if (!ready || refreshed) return;
    setRefreshed(true);
    const saved = trade;
    const refresh = async (item: TradeItem): Promise<TradeItem> => {
      if (item.custom) return item;
      if (item.key.startsWith("h:")) {
        const h = holdings.find((x) => `h:${x.key}` === item.key);
        return h ? { ...item, unit: h.price, maxQty: h.quantity, qty: Math.min(item.qty, h.quantity) } : item;
      }
      const latest = await latestCatalogPrice(item).catch(() => undefined);
      return latest === undefined ? item : { ...item, unit: latest };
    };
    void (async () => {
      const [give, get] = await Promise.all([Promise.all(saved.give.map(refresh)), Promise.all(saved.get.map(refresh))]);
      // Apply refreshed values by item, so edits made meanwhile aren't lost.
      const fresh = new Map([...give, ...get].map((i) => [i.key, i]));
      setStored((cur) => {
        const t = { ...EMPTY, ...cur };
        const merge = (items: TradeItem[]) => items.map((i) => (i.custom ? i : { ...i, ...(fresh.get(i.key) ? { unit: fresh.get(i.key)!.unit, maxQty: fresh.get(i.key)!.maxQty, qty: Math.min(i.qty, fresh.get(i.key)!.maxQty ?? i.qty) } : {}) }));
        return { ...t, give: merge(t.give), get: merge(t.get) };
      });
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once per visit, after the trade loads
  }, [ready, refreshed]);
  const save = (next: TradeState) => setStored(next);

  const give = sideValue(trade.give, trade.rate.give);
  const get = sideValue(trade.get, trade.rate.get);
  const diff = get - give;
  const larger = Math.max(give, get);
  const even = larger === 0 || Math.abs(diff) / larger <= FAIR;
  const hasBoth = trade.give.length > 0 && trade.get.length > 0;

  const update = (side: Side, items: TradeItem[]) => save({ ...trade, [side]: items });
  const add = (side: Side, item: TradeItem) => {
    const existing = trade[side].find((i) => i.key === item.key);
    if (existing) update(side, trade[side].map((i) => (i.key === item.key ? { ...i, qty: Math.min(i.qty + 1, i.maxQty ?? Infinity) } : i)));
    else update(side, [...trade[side], item]);
  };

  const sides = (["give", "get"] as const).map((side) => (
    <TradeMat
      key={side}
      side={side}
      items={trade[side]}
      total={side === "give" ? give : get}
      rate={trade.rate[side]}
      onRate={(r) => save({ ...trade, rate: { ...trade.rate, [side]: r } })}
      onChange={(items) => update(side, items)}
      onAdd={() => setPicking(side)}
      onUseMarket={async (item) => {
        const h = holdings.find((x) => `h:${x.key}` === item.key);
        const latest = h ? h.price : await latestCatalogPrice(item).catch(() => undefined);
        update(side, trade[side].map((i) => (i.key === item.key ? { ...i, custom: false, unit: latest === undefined ? i.unit : latest } : i)));
      }}
    />
  ));

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Trade checker"
        subtitle="Check a trade is fair before you agree to it — valued at today's market prices."
        actions={
          (trade.give.length > 0 || trade.get.length > 0) && (
            <Button variant="ghost" onClick={() => save(EMPTY)}>
              Clear
            </Button>
          )
        }
      />

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_300px_minmax(0,1fr)] lg:items-start">
        <div className="order-2 min-w-0 lg:order-1">{sides[0]}</div>

        {/* The scale */}
        <section aria-live="polite" className="order-1 flex flex-col items-center rounded-[var(--radius-card)] border border-border bg-surface px-5 pb-6 pt-5 text-center lg:order-2 lg:sticky lg:top-6">
          <Scale give={give} get={get} />
          <p className="mt-2 font-mono text-[11px] font-medium uppercase tracking-[0.06em] text-subtle">{hasBoth ? "Verdict" : "Add items to both sides"}</p>
          <p className="mt-2 text-balance text-[22px] font-semibold leading-tight tracking-[-0.02em]">
            {!hasBoth ? (
              "Load up the scale"
            ) : even ? (
              "Fair trade"
            ) : diff > 0 ? (
              <>
                You come out <span className="tabular text-up">{money(diff)}</span> ahead
              </>
            ) : (
              <>
                You give up <span className="tabular text-down">{money(-diff)}</span> more
              </>
            )}
          </p>
          {hasBoth ? (
            <p className="tabular mt-2 text-[12px] text-muted">
              {larger ? pct(Math.abs(diff) / larger, 1) : "0%"} apart · within {pct(FAIR, 0)} counts as even
            </p>
          ) : (
            <p className="mt-2 text-[12px] text-muted">What you give on the left, what you get on the right.</p>
          )}
        </section>

        <div className="order-3 min-w-0">{sides[1]}</div>
      </div>

      <p className="mt-5 flex items-center gap-2 text-[12px] text-subtle">
        <ArrowLeftRight className="size-3.5 shrink-0" /> Uses Holo&apos;s latest saved prices, refreshed each time you open this page. Edit a value to use a price you agreed on.
      </p>

      <PickerDialog side={picking} onClose={() => setPicking(null)} onPick={(item) => picking && add(picking, item)} />
    </div>
  );
}

/* -------------------------------- Scale ---------------------------------- */

/** A balance scale: the beam tips toward the side worth more. */
function Scale({ give, get }: { give: number; get: number }) {
  const larger = Math.max(give, get);
  // Heavier side goes down; full tilt at a 40% difference.
  const tilt = larger ? Math.max(-1, Math.min(1, (get - give) / larger / 0.4)) : 0;
  const angle = tilt * 14;
  const L = 92;
  const rad = (angle * Math.PI) / 180;
  const dx = L * Math.cos(rad);
  const dy = L * Math.sin(rad);
  const cx = 130;
  const cy = 46;
  const t = "transform 700ms cubic-bezier(0.32, 0.72, 0, 1)";
  const pan = (x: number, y: number, label: string, weight: number) => (
    <g style={{ transform: `translate(${x}px, ${y}px)`, transition: t }}>
      <line x1={0} y1={0} x2={-26} y2={44} stroke="currentColor" strokeOpacity={0.35} strokeWidth={1} />
      <line x1={0} y1={0} x2={26} y2={44} stroke="currentColor" strokeOpacity={0.35} strokeWidth={1} />
      <path d="M-34 44 h68 a34 12 0 0 1 -68 0 Z" fill="currentColor" fillOpacity={weight > 0 ? 0.16 : 0.07} stroke="currentColor" strokeOpacity={0.4} strokeWidth={1} />
      <text x={0} y={76} textAnchor="middle" className="fill-[var(--subtle)] font-mono text-[9px] uppercase tracking-[0.08em]">
        {label}
      </text>
    </g>
  );
  return (
    <svg viewBox="0 0 260 150" className="w-full max-w-[280px] text-foreground" aria-hidden>
      {/* Post and base */}
      <path d={`M${cx} ${cy} L${cx} 128`} stroke="currentColor" strokeOpacity={0.5} strokeWidth={3} strokeLinecap="round" />
      <path d={`M${cx - 34} 132 h68`} stroke="currentColor" strokeOpacity={0.5} strokeWidth={3} strokeLinecap="round" />
      {pan(cx - dx, cy - dy, "Give", give)}
      {pan(cx + dx, cy + dy, "Get", get)}
      {/* Beam */}
      <g style={{ transform: `rotate(${angle}deg)`, transformOrigin: `${cx}px ${cy}px`, transition: t }}>
        <line x1={cx - L} y1={cy} x2={cx + L} y2={cy} stroke="currentColor" strokeWidth={3} strokeLinecap="round" />
      </g>
      <circle cx={cx} cy={cy} r={6} className="fill-[var(--surface)]" stroke="currentColor" strokeWidth={2.5} />
    </svg>
  );
}

/* --------------------------------- Mats ---------------------------------- */

function TradeMat({
  side,
  items,
  total,
  rate,
  onRate,
  onChange,
  onAdd,
  onUseMarket,
}: {
  side: Side;
  items: TradeItem[];
  total: number;
  rate: number;
  onRate: (r: number) => void;
  onChange: (items: TradeItem[]) => void;
  onAdd: () => void;
  onUseMarket: (item: TradeItem) => void;
}) {
  const label = side === "give" ? "You give" : "You get";
  const fan = items.flatMap((i) => Array.from({ length: Math.min(i.qty, 3) }, () => i)).slice(0, 6);
  const set = (key: string, patch: Partial<TradeItem>) => onChange(items.map((i) => (i.key === key ? { ...i, ...patch } : i)));
  return (
    <section className={cn("tint hype-surface min-w-0 overflow-hidden rounded-[var(--radius-card)]", side === "give" ? "tint-pink" : "tint-lime")}>
      <div className="flex items-start justify-between gap-3 px-5 pt-5 sm:px-6">
        <div>
          <h2 className="font-display text-[18px] uppercase leading-none tracking-[0.02em] text-foreground/85">{label}</h2>
          <p className="tabular mt-2 font-display text-[36px] leading-none">{money(total)}</p>
        </div>
        <Select value={String(rate)} onValueChange={(v) => onRate(Number(v))}>
          <SelectTrigger aria-label="Count at" className="h-8 w-[150px] text-[12px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent align="end">
            {RATES.map((r) => (
              <SelectItem key={r} value={String(r)}>
                {r === 1 ? "At market value" : `At ${pct(r, 0)} of market`}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* The mat: items fanned out like a hand of cards. */}
      <button
        type="button"
        onClick={onAdd}
        className="group relative mx-5 mt-4 flex h-[168px] w-[calc(100%-2.5rem)] items-end justify-center overflow-hidden rounded-2xl sm:mx-6 sm:w-[calc(100%-3rem)]"
        style={{ background: "radial-gradient(80% 90% at 50% 100%, color-mix(in srgb, var(--foreground) 7%, transparent), transparent), color-mix(in srgb, var(--background) 45%, var(--surface))" }}
        aria-label={`Add to “${label}”`}
      >
        <span aria-hidden className="absolute inset-2 rounded-xl border border-dashed border-border-strong opacity-60 transition-opacity group-hover:opacity-100" />
        {fan.length ? (
          <span className="relative mb-4 flex h-[136px] items-end justify-center">
            {fan.map((item, i) => {
              const mid = (fan.length - 1) / 2;
              return (
                <span
                  key={`${item.key}-${i}`}
                  className="relative -mx-4 block h-[124px] w-[89px] origin-bottom transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1"
                  style={{ transform: `rotate(${(i - mid) * 7}deg) translateY(${Math.abs(i - mid) * 5}px)`, zIndex: i }}
                >
                  <ProductImage product={item.product} size="sm" frame={item.product.kind !== "single"} className="h-full w-full rounded-lg shadow-[0_10px_24px_rgba(0,0,0,0.5)]" />
                </span>
              );
            })}
          </span>
        ) : (
          <span className="relative mb-auto mt-auto flex flex-col items-center gap-2 text-muted transition-colors group-hover:text-foreground">
            <span className="flex size-10 items-center justify-center rounded-full bg-surface-2 ring-1 ring-border">
              <Plus className="size-4" />
            </span>
            <span className="text-[13px] font-medium">{side === "give" ? "Add what you're giving" : "Add what you're getting"}</span>
          </span>
        )}
      </button>

      {items.length > 0 && (
        <ul className="mt-2 divide-y divide-border px-5 sm:px-6">
          {items.map((item) => (
            <li key={item.key} className="flex items-center gap-3 py-3">
              <ProductImage product={item.product} size="xs" className="size-10 shrink-0 rounded-lg" />
              <div className="min-w-0 flex-1">
                <p className="truncate text-[13px] font-medium">{item.product.name}</p>
                <div className="mt-1 flex flex-wrap items-center gap-2">
                  <div className="flex items-center rounded-full bg-surface-2">
                    <button aria-label="Fewer" className="flex size-6 items-center justify-center text-muted hover:text-foreground disabled:opacity-30" disabled={item.qty <= 1} onClick={() => set(item.key, { qty: item.qty - 1 })}>
                      <Minus className="size-3" />
                    </button>
                    <span className="tabular w-5 text-center text-[12px]">{item.qty}</span>
                    <button aria-label="More" className="flex size-6 items-center justify-center text-muted hover:text-foreground disabled:opacity-30" disabled={item.maxQty !== undefined && item.qty >= item.maxQty} onClick={() => set(item.key, { qty: item.qty + 1 })}>
                      <Plus className="size-3" />
                    </button>
                  </div>
                  <span className="relative">
                    <span className="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 text-[12px] text-subtle">$</span>
                    <input
                      inputMode="decimal"
                      aria-label="Value each"
                      value={item.unit ?? ""}
                      placeholder="Value"
                      onChange={(e) => {
                        const v = e.target.value.replace(/[^0-9.]/g, "");
                        set(item.key, { unit: v === "" ? null : Number(v), custom: true });
                      }}
                      className="tabular h-6 w-20 rounded-full bg-surface-2 pl-5 pr-2 text-[12px] text-foreground outline-none focus:bg-surface-3"
                    />
                  </span>
                  {item.custom && (
                    <button className="text-[11px] text-subtle underline-offset-4 hover:text-foreground hover:underline" onClick={() => onUseMarket(item)}>
                      Use market
                    </button>
                  )}
                </div>
              </div>
              <p className="tabular shrink-0 text-[14px] font-semibold">{item.unit === null ? <span className="text-subtle">—</span> : money(item.unit * item.qty)}</p>
              <button aria-label={`Remove ${item.product.name}`} className="shrink-0 text-subtle hover:text-foreground" onClick={() => onChange(items.filter((i) => i.key !== item.key))}>
                <Trash2 className="size-3.5" />
              </button>
            </li>
          ))}
        </ul>
      )}

      <div className="px-5 pb-5 pt-2 sm:px-6 sm:pb-6">
        {items.length > 0 && (
          <Button variant="secondary" className="w-full" onClick={onAdd}>
            <Plus /> Add more
          </Button>
        )}
      </div>
    </section>
  );
}

/* ------------------------------- Picker ---------------------------------- */

function PickerDialog({ side, onClose, onPick }: { side: Side | null; onClose: () => void; onPick: (item: TradeItem) => void }) {
  const { holdings } = usePortfolio();
  const [source, setSource] = useState<"collection" | "catalog">("catalog");
  const [q, setQ] = useState("");
  const [results, setResults] = useState<ExploreProduct[] | null>(null);
  const [loading, setLoading] = useState(false);

  // Giving usually comes from your collection; getting from anywhere.
  useEffect(() => {
    if (side) {
      setSource(side === "give" && holdings.length ? "collection" : "catalog");
      setQ("");
      setResults(null);
    }
  }, [side, holdings.length]);

  useEffect(() => {
    if (source !== "catalog" || q.trim().length < 2) return setResults(null);
    setLoading(true);
    const t = window.setTimeout(() => {
      fetch(`/api/explore/search?q=${encodeURIComponent(q.trim())}`)
        .then((r) => (r.ok ? r.json() : { products: [] }))
        .then((b) => setResults(b.products ?? []))
        .catch(() => setResults([]))
        .finally(() => setLoading(false));
    }, 300);
    return () => window.clearTimeout(t);
  }, [q, source]);

  const mine = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return holdings.filter((h) => h.product && (!needle || `${h.product.name} ${h.product.setName}`.toLowerCase().includes(needle)));
  }, [holdings, q]);

  const pick = (item: TradeItem) => {
    onPick(item);
    onClose();
  };

  return (
    <Dialog open={side !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="h-[80dvh] sm:h-[600px] sm:max-w-[540px]" aria-describedby={undefined}>
        <div className="px-6 pt-6">
          <DialogTitle>{side === "give" ? "What are you giving?" : "What are you getting?"}</DialogTitle>
          <div className="relative mt-4">
            <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
            <input
              autoFocus
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder={source === "collection" ? "Filter your collection" : "Search cards and sealed"}
              aria-label="Search"
              className="h-11 w-full rounded-2xl bg-surface-2 pl-10 pr-3 text-[15px] outline-none placeholder:text-subtle focus:bg-surface-3"
            />
          </div>
          <div className="mt-3">
            <Segmented
              ariaLabel="Source"
              size="sm"
              value={source}
              onChange={setSource}
              options={[
                { value: "collection", label: "Your collection" },
                { value: "catalog", label: "Catalog" },
              ]}
            />
          </div>
        </div>
        <div className="mt-3 min-h-0 flex-1 overflow-y-auto px-3 pb-4">
          {source === "collection" ? (
            mine.length ? (
              mine.map((h) => (
                <PickRow
                  key={h.key}
                  product={h.product!}
                  sub={`You own ${h.quantity}`}
                  price={h.price}
                  onClick={() => pick({ key: `h:${h.key}`, product: h.product!, unit: h.price, qty: 1, maxQty: h.quantity })}
                />
              ))
            ) : (
              <p className="px-3 py-10 text-center text-[14px] text-muted">Nothing in your collection matches.</p>
            )
          ) : loading ? (
            <p className="flex items-center justify-center gap-2 py-10 text-[14px] text-muted">
              <Loader2 className="size-4 animate-spin" /> Searching…
            </p>
          ) : results === null ? (
            <p className="px-3 py-10 text-center text-[14px] text-muted">Type at least two letters to search the catalog.</p>
          ) : results.length ? (
            results.map((r) => (
              <PickRow
                key={r.product.id}
                product={r.product}
                sub={[r.gameName, r.product.setName, r.product.number && `#${r.product.number}`].filter(Boolean).join(" · ")}
                price={r.market}
                onClick={() => pick({ key: `p:${r.product.id}`, product: r.product, unit: r.market, qty: 1, printing: r.printing })}
              />
            ))
          ) : (
            <p className="px-3 py-10 text-center text-[14px] text-muted">Nothing in the catalog matches yet.</p>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function PickRow({ product, sub, price, onClick }: { product: Product; sub: string; price: number | null; onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors hover:bg-surface-2">
      <ProductImage product={product} size="xs" className="size-11 shrink-0 rounded-lg" />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[14px] font-medium">{product.name}</span>
        <span className="block truncate text-[12px] text-muted">{sub}</span>
      </span>
      <span className="tabular shrink-0 text-[14px] font-medium">{price === null ? <span className="text-subtle">No price</span> : money(price)}</span>
    </button>
  );
}
