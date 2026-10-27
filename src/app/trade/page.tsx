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
import { money, pct, signedMoney } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import type { Product } from "@/lib/types";

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

function persist(next: TradeState) {
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    // ignore
  }
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
  const [trade, setTrade] = useState<TradeState>(EMPTY);
  const [picking, setPicking] = useState<Side | null>(null);
  const { status } = useStore();
  const { holdings } = usePortfolio({ ignoreFilter: true });

  // Keep the trade in progress in this browser, and refresh every value that
  // wasn't typed in to the latest saved price each time the page opens.
  useEffect(() => {
    if (status !== "ready") return;
    let saved: TradeState = EMPTY;
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) saved = { ...EMPTY, ...(JSON.parse(raw) as TradeState) };
    } catch {
      // ignore
    }
    setTrade(saved);
    let cancelled = false;
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
      const next = { ...saved, give: await Promise.all(saved.give.map(refresh)), get: await Promise.all(saved.get.map(refresh)) };
      if (cancelled) return;
      setTrade(next);
      persist(next);
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once per visit, after the collection loads
  }, [status]);
  const save = (next: TradeState) => {
    setTrade(next);
    persist(next);
  };

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

      {/* Verdict */}
      <section aria-live="polite" className="rounded-[var(--radius-card)] border border-border bg-surface p-5 sm:p-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="text-[12px] font-semibold uppercase tracking-[0.12em] text-muted">{hasBoth ? "Verdict" : "Add items to both sides"}</p>
            <p className="mt-2 text-[26px] font-semibold leading-tight tracking-[-0.02em] sm:text-[30px]">
              {!hasBoth ? (
                "—"
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
            {hasBoth && (
              <p className="tabular mt-1 text-[13px] text-muted">
                {signedMoney(diff)} ({larger ? pct(diff / larger, 1) : "0%"}) · within {pct(FAIR, 0)} counts as even
              </p>
            )}
          </div>
          <div className="tabular flex gap-6 text-right">
            <div>
              <p className="text-[12px] text-muted">You give</p>
              <p className="text-[20px] font-semibold">{money(give)}</p>
            </div>
            <div>
              <p className="text-[12px] text-muted">You get</p>
              <p className="text-[20px] font-semibold">{money(get)}</p>
            </div>
          </div>
        </div>
        {/* Balance bar */}
        <div className="mt-5 flex h-2.5 overflow-hidden rounded-full bg-surface-2" aria-hidden>
          {larger > 0 && (
            <>
              <div className="h-full bg-[var(--cat-2)] transition-[flex-grow] duration-500" style={{ flexGrow: give }} />
              <div className="w-[2px] bg-background" />
              <div className="h-full bg-[var(--cat-1)] transition-[flex-grow] duration-500" style={{ flexGrow: get }} />
            </>
          )}
        </div>
      </section>

      <div className="mt-5 grid gap-5 lg:grid-cols-2">
        {(["give", "get"] as const).map((side) => (
          <section key={side} className="min-w-0 rounded-[var(--radius-card)] border border-border bg-surface p-5 sm:p-6">
            <div className="flex items-center justify-between gap-3">
              <h2 className="flex items-center gap-2 text-[17px] font-semibold">
                <span className="size-2.5 rounded-full" style={{ background: side === "give" ? "var(--cat-2)" : "var(--cat-1)" }} />
                {side === "give" ? "You give" : "You get"}
              </h2>
              <Select value={String(trade.rate[side])} onValueChange={(v) => save({ ...trade, rate: { ...trade.rate, [side]: Number(v) } })}>
                <SelectTrigger aria-label="Count at" className="h-8 w-[150px] text-[13px]">
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

            <ul className="mt-4 divide-y divide-border">
              {trade[side].map((item) => (
                <li key={item.key} className="flex items-center gap-3 py-3">
                  <ProductImage product={item.product} size="xs" className="size-12 shrink-0 rounded-lg" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[14px] font-medium">{item.product.name}</p>
                    <div className="mt-1 flex items-center gap-2">
                      <div className="flex items-center rounded-full bg-surface-2">
                        <button aria-label="Fewer" className="flex size-7 items-center justify-center text-muted hover:text-foreground disabled:opacity-30" disabled={item.qty <= 1} onClick={() => update(side, trade[side].map((i) => (i.key === item.key ? { ...i, qty: i.qty - 1 } : i)))}>
                          <Minus className="size-3" />
                        </button>
                        <span className="tabular w-5 text-center text-[12px]">{item.qty}</span>
                        <button
                          aria-label="More"
                          className="flex size-7 items-center justify-center text-muted hover:text-foreground disabled:opacity-30"
                          disabled={item.maxQty !== undefined && item.qty >= item.maxQty}
                          onClick={() => update(side, trade[side].map((i) => (i.key === item.key ? { ...i, qty: i.qty + 1 } : i)))}
                        >
                          <Plus className="size-3" />
                        </button>
                      </div>
                      <label className="flex items-center gap-1 text-[12px] text-muted">
                        ×
                        <span className="relative">
                          <span className="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 text-subtle">$</span>
                          <input
                            inputMode="decimal"
                            aria-label="Value each"
                            value={item.unit ?? ""}
                            placeholder="Value"
                            onChange={(e) => {
                              const v = e.target.value.replace(/[^0-9.]/g, "");
                              update(side, trade[side].map((i) => (i.key === item.key ? { ...i, unit: v === "" ? null : Number(v), custom: true } : i)));
                            }}
                            className="tabular h-7 w-24 rounded-full bg-surface-2 pl-5 pr-2 text-[12px] text-foreground outline-none focus:bg-surface-3"
                          />
                        </span>
                      </label>
                      {item.custom && (
                        <button
                          className="text-[12px] text-subtle underline-offset-4 hover:text-foreground hover:underline"
                          onClick={async () => {
                            const h = holdings.find((x) => `h:${x.key}` === item.key);
                            const latest = h ? h.price : await latestCatalogPrice(item).catch(() => undefined);
                            update(side, trade[side].map((i) => (i.key === item.key ? { ...i, custom: false, unit: latest === undefined ? i.unit : latest } : i)));
                          }}
                        >
                          Use market
                        </button>
                      )}
                    </div>
                  </div>
                  <div className="shrink-0 text-right">
                    <p className="tabular text-[14px] font-semibold">{item.unit === null ? <span className="text-subtle">—</span> : money(item.unit * item.qty)}</p>
                    <button aria-label={`Remove ${item.product.name}`} className="mt-1 text-subtle hover:text-down" onClick={() => update(side, trade[side].filter((i) => i.key !== item.key))}>
                      <Trash2 className="size-3.5" />
                    </button>
                  </div>
                </li>
              ))}
            </ul>

            <Button variant="secondary" className="mt-3 w-full" onClick={() => setPicking(side)}>
              <Plus /> Add to “{side === "give" ? "You give" : "You get"}”
            </Button>
          </section>
        ))}
      </div>

      <p className="mt-5 flex items-center gap-2 text-[12px] text-subtle">
        <ArrowLeftRight className="size-3.5" /> Uses Holo&apos;s latest saved prices, refreshed each time you open this page. Edit a value to use a price you agreed on.
      </p>

      <PickerDialog side={picking} onClose={() => setPicking(null)} onPick={(item) => picking && add(picking, item)} />
    </div>
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
