"use client";

import { Check, PencilLine, Plus, Search } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import type { ExploreProduct } from "@/lib/explore/types";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money } from "@/lib/format";
import { usePortfolio } from "@/lib/store/collection-store";
import type { Grade, Product } from "@/lib/types";
import { cn } from "@/lib/utils";

export type DealSide = "in" | "out";

/** A row in a deal: from your inventory (`holdingKey`), the catalog, or a custom line. Same JSON as the app's DealItem. */
export interface DealItem {
  key: string;
  product: Product;
  printing?: string | null;
  /** Market value per unit when added (or as agreed by hand; see catalogMarket). */
  market: number | null;
  qty: number;
  /** Negotiated price per unit; null means market × the rate. */
  price: number | null;
  /** This item's own share of market, overriding the side's rate. */
  rate?: number | null;
  /** A slab's grade, as scanned, for items coming in that aren't already held. */
  grade?: Grade | null;
  /** The holding this came from, when picked from your inventory. */
  holdingKey?: string;
  maxQty?: number;
  /** Coming in: false keeps it out of your collection (unset follows your deal settings). */
  track?: boolean | null;
  /** Going out but not in Holo: what you paid per unit, if you said. */
  cost?: number | null;
  /** A line that isn't a catalog product ("Bulk lot"): a name and a price, never tracked. */
  custom?: boolean;
  /** The catalog's market price, kept when the market was changed by hand, so it can be put back. */
  catalogMarket?: number | null;
}

/** "Charizard ex" for "Charizard ex - 199/165": the name without its number on the end (the app's shortName). */
export function shortName(p: Pick<Product, "name" | "number">): string {
  const n = p.number;
  return n && p.name.endsWith(` - ${n}`) ? p.name.slice(0, -(n.length + 3)) : p.name;
}

/**
 * Add cards to one side of the deal, like the app's DealPickerSheet: coming in searches the
 * catalog ("Add cards"); going out lists your collection first, then the catalog for things you
 * have that aren't in it yet ("Add from your collection"). Tap a row to add it, again to take it
 * off. Not in the catalog at all: "Add a custom item or lot" (a name and a price).
 */
export function DealPicker({
  side,
  onDeal,
  onClose,
  onPick,
  onRemove,
}: {
  side: DealSide | null;
  /** Keys already on this side (ticked). */
  onDeal: Set<string>;
  onClose: () => void;
  onPick: (item: DealItem) => void;
  onRemove: (key: string) => void;
}) {
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const [customOpen, setCustomOpen] = useState(false);
  const [custom, setCustom] = useState({ name: "", price: "", qty: "1" });
  const [q, setQ] = useState("");
  const [results, setResults] = useState<ExploreProduct[] | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (side) {
      setCustomOpen(false);
      setCustom({ name: "", price: "", qty: "1" });
      setQ("");
      setResults(null);
    }
  }, [side]);

  useEffect(() => {
    if (q.trim().length < 2) return setResults(null);
    setLoading(true);
    const t = window.setTimeout(() => {
      fetch(`/api/explore/search?q=${encodeURIComponent(q.trim())}`)
        .then((r) => (r.ok ? r.json() : { products: [] }))
        .then((b) => setResults(b.products ?? []))
        .catch(() => setResults([]))
        .finally(() => setLoading(false));
    }, 300);
    return () => window.clearTimeout(t);
  }, [q]);

  const mine = useMemo(() => {
    if (side !== "out") return [];
    const needle = q.trim().toLowerCase();
    const all = holdings.filter((h) => h.product);
    if (!needle) return all.slice(0, 40);
    return all.filter((h) => `${h.product!.name} ${h.product!.setName ?? ""} ${h.product!.number ?? ""}`.toLowerCase().includes(needle));
  }, [holdings, q, side]);

  const fromHolding = (h: HoldingView): DealItem => ({ key: `h:${h.key}`, product: h.product!, printing: h.identity.printing, market: h.price, qty: 1, price: null, holdingKey: h.key, maxQty: side === "out" ? h.quantity : undefined });
  const toggle = (item: DealItem) => (onDeal.has(item.key) ? onRemove(item.key) : onPick(item));

  const panel = (title: string, line: string) => (
    <div className="rounded-[20px] bg-white/[0.05] p-[18px] ring-1 ring-inset ring-white/[0.08]">
      <p className="font-display text-[20px] leading-tight tracking-[-0.02em]">{title}</p>
      <p className="mt-1 text-[14px] text-muted">{line}</p>
      <button type="button" onClick={() => setCustomOpen(true)} className="glass-stat mt-3.5 flex h-[46px] w-full items-center justify-center gap-2 rounded-full text-[15px] font-semibold hover:bg-white/[0.08]">
        <PencilLine className="size-4" /> Add a custom item or lot
      </button>
    </div>
  );

  const searching = q.trim().length >= 2;
  return (
    <Dialog open={side !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="h-[88dvh] bg-[#161618] sm:h-[640px] sm:max-w-[540px]" aria-describedby={undefined}>
        {customOpen ? (
          <form
            className="flex flex-col gap-3 px-5 pb-6 pt-6"
            onSubmit={(e) => {
              e.preventDefault();
              const price = Number(custom.price.replace(/[$,]/g, ""));
              if (!custom.name.trim() || !(price > 0)) return;
              const id = crypto.randomUUID();
              onPick({
                key: `c:${id}`,
                product: { id: `custom:${id}`, source: "manual", externalId: id, name: custom.name.trim(), setName: null, setId: null, number: null, rarity: null, productType: "Custom", kind: "sealed", imageUrl: null, tcgplayerId: null, tcgplayerUrl: null },
                market: null,
                qty: Math.max(1, Math.round(Number(custom.qty) || 1)),
                price,
                custom: true,
              });
              onClose();
            }}
          >
            <DialogTitle className="font-display text-[22px] tracking-[-0.02em]">A custom item or lot</DialogTitle>
            <p className="text-[14px] text-muted">A lot, a binder or anything not in the catalog. Counted in the deal, not tracked in your collection.</p>
            <input autoFocus value={custom.name} onChange={(e) => setCustom({ ...custom, name: e.target.value })} placeholder="What is it?" aria-label="Name" className="h-11 w-full rounded-2xl bg-white/[0.06] px-3.5 text-[15px] outline-none ring-1 ring-inset ring-white/[0.08] placeholder:text-subtle focus:ring-white/25" />
            <div className="flex gap-2">
              <input value={custom.price} onChange={(e) => setCustom({ ...custom, price: e.target.value })} inputMode="decimal" placeholder="Price each" aria-label="Price each" className="tabular h-11 min-w-0 flex-1 rounded-2xl bg-white/[0.06] px-3.5 text-[15px] outline-none ring-1 ring-inset ring-white/[0.08] placeholder:text-subtle focus:ring-white/25" />
              <input value={custom.qty} onChange={(e) => setCustom({ ...custom, qty: e.target.value })} inputMode="numeric" aria-label="Quantity" className="tabular h-11 w-20 rounded-2xl bg-white/[0.06] px-3.5 text-[15px] outline-none ring-1 ring-inset ring-white/[0.08] focus:ring-white/25" />
            </div>
            <div className="mt-1 flex gap-2">
              <button type="button" onClick={() => setCustomOpen(false)} className="btn-3d btn-3d-dark h-11 rounded-full bg-surface-2 px-5 text-[15px] font-semibold">
                Back
              </button>
              <button type="submit" className="btn-3d btn-3d-lime h-11 flex-1 rounded-full bg-lime text-[15px] font-semibold text-[#0b0b0c] disabled:opacity-50" disabled={!custom.name.trim() || !(Number(custom.price.replace(/[$,]/g, "")) > 0)}>
                Add to deal
              </button>
            </div>
          </form>
        ) : (
          <>
            <div className="px-4 pt-6">
              <DialogTitle className="px-1 font-display text-[22px] tracking-[-0.02em]">{side === "out" ? "Add from your collection" : "Add cards"}</DialogTitle>
              <div className="relative mt-3.5">
                <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
                <input
                  autoFocus
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder={side === "out" ? "Search your collection or any card" : "Search any card or product"}
                  aria-label="Search"
                  className="glass-stat h-11 w-full rounded-full pl-10 pr-3 text-[15px] outline-none placeholder:text-subtle focus:ring-1 focus:ring-white/25"
                />
              </div>
            </div>
            <div className="mt-2 min-h-0 flex-1 overflow-y-auto px-4 pb-5">
              {side === "in" && !searching && <div className="pt-2">{panel("Find their cards", "Search by name, set or number above. Not in the catalog? Add it by hand.")}</div>}
              {side === "out" && (
                <>
                  <p className="px-1 pb-1 pt-3 font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">Your collection</p>
                  {mine.length ? (
                    mine.map((h) => {
                      const item = fromHolding(h);
                      return <Row key={h.key} product={h.product!} sub={`You have ${h.quantity}${h.identity.grade ? ` · ${h.identity.grade.company} ${h.identity.grade.grade}` : ""}`} line={h.product!.setName} price={h.price} on={onDeal.has(item.key)} onClick={() => toggle(item)} />;
                    })
                  ) : (
                    <p className="px-1 py-3 text-[14px] text-muted">Nothing matches.</p>
                  )}
                </>
              )}
              {searching && (
                <>
                  {side === "out" && <p className="px-1 pb-1 pt-4 font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">Not in Corodex</p>}
                  {loading && !results?.length ? (
                    <div className="space-y-2 pt-2">
                      {[0, 1, 2].map((i) => (
                        <div key={i} className="h-[89px] rounded-xl bg-white/[0.04]" />
                      ))}
                    </div>
                  ) : results?.length ? (
                    results.map((r) => {
                      const item: DealItem = { key: `p:${r.product.id}:${r.printing ?? ""}:`, product: r.product, printing: r.printing, market: r.market, qty: 1, price: null };
                      return <Row key={item.key} product={r.product} line={r.product.setName} sub={r.product.number ? `#${r.product.number}` : null} price={r.market} on={onDeal.has(item.key)} onClick={() => toggle(item)} />;
                    })
                  ) : (
                    <p className="px-1 py-3 text-[14px] text-muted">Nothing in the catalog matches yet.</p>
                  )}
                  {side === "out" && results && results.length > 0 && <p className="px-1 pt-2 text-[13px] text-muted">Something you have that isn&apos;t in your collection yet. Add what you paid on the deal and it&apos;s recorded properly; otherwise it&apos;s counted in the deal but not tracked.</p>}
                </>
              )}
              {(side === "out" || searching) && <div className="pt-4">{panel("Can't find it?", "Add a lot, a binder or anything not in the catalog. A name and a price is enough.")}</div>}
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function Row({ product, line, sub, price, on, onClick }: { product: Product; line?: string | null; sub?: string | null; price: number | null; on: boolean; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={on} className="flex w-full items-center gap-3 rounded-xl py-1.5 text-left transition-colors hover:bg-white/[0.03]">
      <ProductImage product={product} size="sm" className="h-[89px] w-16 shrink-0 rounded-[4px]" />
      <span className="min-w-0 flex-1">
        <span className="line-clamp-2 text-[16px] font-medium leading-snug">{shortName(product)}</span>
        {line && <span className="block truncate text-[13px] text-muted">{line}</span>}
        {sub && <span className="block truncate text-[12px] text-subtle">{sub}</span>}
      </span>
      <span className="tabular shrink-0 text-[16px] font-semibold">{price === null ? <span className="text-[13px] font-normal text-subtle">No price</span> : money(price)}</span>
      <span className={cn("flex size-[22px] shrink-0 items-center justify-center rounded-full", on ? "bg-lime text-[#0b0b0c]" : "text-white/35 ring-[1.5px] ring-inset ring-white/35")}>{on ? <Check className="size-3.5" strokeWidth={3} /> : <Plus className="size-3.5" strokeWidth={2.5} />}</span>
    </button>
  );
}
