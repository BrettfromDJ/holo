"use client";

import { Check, Copy, PlusCircle, Search, X } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { ProductImage } from "@/components/product/product-image";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import type { ExploreProduct } from "@/lib/explore/types";
import { money } from "@/lib/format";
import type { ListMeta } from "@/lib/lists";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useShelves } from "@/lib/store/shelves";
import type { Product } from "@/lib/types";
import { cn } from "@/lib/utils";
import { productSubtitle, shortName } from "./list-row";
import { useListMeta, useListShare } from "./use-lists";

const limeWide = "flex h-[52px] w-full items-center justify-center rounded-full bg-lime text-[16px] font-semibold text-[#0b0b0c] transition-[transform,opacity] active:scale-[0.98] disabled:opacity-40";

/** Title and a round close, like the app's `SheetHeader`. */
function SheetHeader({ title, onClose }: { title: string; onClose: () => void }) {
  return (
    <div className="flex items-center justify-between">
      <DialogTitle className="text-[17px] font-semibold">{title}</DialogTitle>
      <button type="button" onClick={onClose} aria-label="Close" className="flex size-[34px] items-center justify-center rounded-full bg-foreground/10 transition-colors hover:bg-foreground/15">
        <X className="size-3.5" strokeWidth={2.5} />
      </button>
    </div>
  );
}

function MonoLabel({ children }: { children: React.ReactNode }) {
  return <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-muted">{children}</p>;
}

/** Name a list (new or rename): a box and a lime button, nothing else (the app's `ListNameSheet`). */
export function ListNameDialog({ open, onOpenChange, title, action, initial = "", onSave }: { open: boolean; onOpenChange: (o: boolean) => void; title: string; action: string; initial?: string; onSave: (name: string) => Promise<void> }) {
  const [text, setText] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ref = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (open) {
      setText(initial);
      setError(null);
    }
  }, [open, initial]);
  const name = text.trim().slice(0, 40);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        hideClose
        aria-describedby={undefined}
        className="gap-3.5 p-5 sm:max-w-md"
        onOpenAutoFocus={(e) => {
          e.preventDefault();
          ref.current?.focus();
        }}
      >
        <SheetHeader title={title} onClose={() => onOpenChange(false)} />
        <form
          className="flex flex-col gap-3.5"
          onSubmit={async (e) => {
            e.preventDefault();
            if (!name || saving) return;
            setSaving(true);
            try {
              await onSave(name);
              onOpenChange(false);
            } catch (err) {
              setError(err instanceof Error ? err.message : "Couldn't save the list.");
            } finally {
              setSaving(false);
            }
          }}
        >
          <input
            ref={ref}
            value={text}
            onChange={(e) => setText(e.target.value)}
            maxLength={40}
            placeholder="Favorite SIRs, For sale at the show…"
            aria-label="List name"
            className="h-[52px] rounded-2xl bg-foreground/[0.08] px-4 text-[17px] outline-none placeholder:text-subtle"
          />
          <button type="submit" className={limeWide} disabled={!name || saving}>
            {action}
          </button>
          {error && <p className="text-[13px]">{error}</p>}
        </form>
      </DialogContent>
    </Dialog>
  );
}

const PERCENTS = [100, 95, 90, 85, 80, 75, 70, 65, 60];

/** A card's asking price on a list for sale: the list's %, its own %, or a set price (the app's `ListItemPriceSheet`). */
export function ListItemPriceDialog({ listId, productId, product, market, onClose }: { listId: string; productId: string | null; product: Product | undefined; market: number | null; onClose: () => void }) {
  const { meta, update } = useListMeta();
  const m: ListMeta = meta(listId);
  const listPercent = m.askPercent ?? 100;
  const [percent, setPercent] = useState<number | null>(null);
  const [priceText, setPriceText] = useState("");
  useEffect(() => {
    if (!productId) return;
    setPercent(m.percents?.[productId] ?? null);
    const own = m.prices?.[productId];
    setPriceText(own != null ? own.toFixed(2) : "");
    // eslint-disable-next-line react-hooks/exhaustive-deps -- read once per card opened
  }, [productId]);
  const typedRaw = Number.parseFloat(priceText.replace(/[^0-9.]/g, ""));
  const typed = priceText.trim() && Number.isFinite(typedRaw) && typedRaw >= 0 ? typedRaw : null;
  const shown = percent ?? listPercent;
  const asking = typed ?? (market === null ? null : Math.round(market * shown) / 100);

  const save = () => {
    if (!productId) return;
    update(listId, (prev) => {
      const prices = { ...(prev.prices ?? {}) };
      const percents = { ...(prev.percents ?? {}) };
      if (typed !== null) prices[productId] = typed;
      else delete prices[productId];
      if (typed === null && percent !== null) percents[productId] = percent;
      else delete percents[productId];
      return { ...prev, prices, percents };
    });
    onClose();
  };

  return (
    <Dialog open={productId !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent hideClose aria-describedby={undefined} className="gap-[22px] px-5 pb-5 pt-6 sm:max-w-md">
        <SheetHeader title="Your price" onClose={onClose} />
        <div className="flex items-center gap-3.5">
          <ProductImage product={product} size="xs" className="h-[67px] w-12 shrink-0" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-[15px] font-semibold">{shortName(product)}</p>
            <p className="tabular text-[13px] text-muted">Market {money(market)}</p>
          </div>
          <div className="text-right">
            <p className="font-display tabular text-[30px] leading-none">{money(asking)}</p>
            <p className="mt-1 text-[12px] text-muted">{typed !== null ? "your price" : `${shown}% of market`}</p>
          </div>
        </div>
        <div className="space-y-2">
          <MonoLabel>Percentage of market</MonoLabel>
          <div className="fade-row flex gap-2 overflow-x-auto pb-0.5 [scrollbar-width:none]" data-fade-end="true">
            {PERCENTS.map((p) => (
              <button
                key={p}
                type="button"
                aria-pressed={typed === null && shown === p}
                onClick={() => {
                  // Picking the list's own % goes back to following the list.
                  setPercent(p === listPercent ? null : p);
                  setPriceText("");
                }}
                className="lists-chip h-9 shrink-0 rounded-[13px] px-3.5 text-[14px] font-medium"
              >
                {p}%
              </button>
            ))}
          </div>
          <p className="text-[12px] text-subtle">{percent === null && typed === null ? `Follows the list's ${listPercent}%.` : `The list asks ${listPercent}%; this card has its own price.`}</p>
        </div>
        <div className="space-y-2">
          <MonoLabel>Or a set price</MonoLabel>
          <label className={cn("flex h-12 items-center gap-1 rounded-[14px] border bg-foreground/[0.06] px-3.5 text-[17px]", typed !== null ? "border-lime" : "border-border")}>
            <span className="text-muted">$</span>
            <input inputMode="decimal" value={priceText} onChange={(e) => setPriceText(e.target.value)} placeholder="Type a price" aria-label="Set price" className="tabular min-w-0 flex-1 bg-transparent outline-none placeholder:text-subtle" />
          </label>
        </div>
        <button type="button" onClick={save} className={limeWide}>
          Save
        </button>
      </DialogContent>
    </Dialog>
  );
}

/** Put cards on a list: from your collection, or anything in our catalog (the app's `ListAddSheet`). */
export function ListAddDialog({ listId, open, onOpenChange }: { listId: string; open: boolean; onOpenChange: (o: boolean) => void }) {
  const store = useStore();
  const { shelves, toggle, addMany } = useShelves();
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const [q, setQ] = useState("");
  const [results, setResults] = useState<ExploreProduct[] | null>(null);
  const [loading, setLoading] = useState(false);
  const onList = useMemo(() => new Set(shelves.find((s) => s.id === listId)?.productIds ?? []), [shelves, listId]);

  useEffect(() => {
    if (!open) setQ("");
  }, [open]);

  useEffect(() => {
    if (q.trim().length < 2) return setResults(null);
    setLoading(true);
    const t = window.setTimeout(() => {
      fetch(`/api/explore/search?q=${encodeURIComponent(q.trim())}`)
        .then((r) => (r.ok ? r.json() : { products: [] }))
        .then((b: { products?: ExploreProduct[] }) => setResults(b.products ?? []))
        .catch(() => setResults([]))
        .finally(() => setLoading(false));
    }, 300);
    return () => window.clearTimeout(t);
  }, [q]);

  const owned = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const seen = new Set<string>();
    const all = holdings
      .filter((h) => h.product && h.quantity > 0)
      .sort((a, b) => (b.value ?? 0) - (a.value ?? 0))
      .filter((h) => (seen.has(h.identity.productId) ? false : (seen.add(h.identity.productId), true)));
    if (!needle) return all.slice(0, 60);
    return all.filter((h) => `${h.product!.name} ${h.product!.setName ?? ""} ${h.product!.number ?? ""}`.toLowerCase().includes(needle));
  }, [holdings, q]);

  const flip = (productId: string, product?: Product) => {
    const run = onList.has(productId) ? toggle(listId, productId) : addMany(listId, [productId]);
    run.then(
      () => {
        if (product && !onList.has(productId) && !store.data.products[productId]) void store.showCatalogProduct(productId);
      },
      (err: Error) => toast.error(err.message),
    );
  };

  const row = (key: string, productId: string, product: Product | undefined, price: number | null) => {
    const on = onList.has(productId);
    return (
      <li key={key}>
        <button type="button" onClick={() => flip(productId, product)} className="flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left transition-colors hover:bg-foreground/[0.05]">
          <ProductImage product={product} size="xs" className="h-[50px] w-9 shrink-0" />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-[14px] font-medium">{shortName(product)}</span>
            <span className="block truncate text-[12px] text-muted">{productSubtitle(product)}</span>
          </span>
          <span className="tabular text-[13px] text-muted">{money(price)}</span>
          {on ? (
            <span className="flex size-5 items-center justify-center rounded-full bg-lime text-[#0b0b0c]">
              <Check className="size-3" strokeWidth={3} />
            </span>
          ) : (
            <PlusCircle className="size-5 text-foreground/30" />
          )}
        </button>
      </li>
    );
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideClose aria-describedby={undefined} className="h-[85dvh] sm:h-[640px] sm:max-w-[540px]">
        <div className="px-5 pt-5">
          <SheetHeader title="Add cards" onClose={() => onOpenChange(false)} />
          <div className="relative mt-4">
            <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
            <input
              autoFocus
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search your cards or any card"
              aria-label="Search"
              className="lists-glass h-11 w-full rounded-full pl-10 pr-3 text-[15px] outline-none placeholder:text-subtle"
            />
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-5 pt-3">
          {q.trim().length >= 2 && (
            <section className="mb-4">
              <MonoLabel>
                <span className="px-2">Catalog</span>
              </MonoLabel>
              {results && !results.length && !loading && <p className="px-2 py-3 text-[14px] text-muted">Nothing found.</p>}
              <ul className="mt-1">{(results ?? []).map((r) => row(`c:${r.product.id}`, r.product.id, r.product, r.market))}</ul>
            </section>
          )}
          <section>
            <MonoLabel>
              <span className="px-2">Your collection</span>
            </MonoLabel>
            {!owned.length && <p className="px-2 py-3 text-[14px] text-muted">Nothing matches.</p>}
            <ul className="mt-1">{owned.map((h) => row(`h:${h.identity.productId}`, h.identity.productId, h.product, h.price))}</ul>
          </section>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** A list's link: anyone with it sees the cards and prices (and asking prices when for sale), never what you paid. */
export function ListShareDialog({ listId, name, forSale, open, onOpenChange }: { listId: string; name: string; forSale: boolean; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { canShare, token, error, stop } = useListShare(listId, open);
  const url = token && typeof window !== "undefined" ? `${window.location.origin}/l/${token}` : "";
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideClose className="gap-5 p-5 sm:max-w-md">
        <SheetHeader title="Share list" onClose={() => onOpenChange(false)} />
        <div className="text-center">
          <p className="font-display text-balance text-[26px] leading-tight">{name}</p>
          <DialogDescription className="mx-auto mt-1.5 max-w-sm text-pretty text-[14px] text-muted">
            {forSale ? "Show this to a vendor. They see each card, its condition, market price and your asking price. Never what you paid." : "Anyone with the link sees the cards on this list and their market prices. Never what you paid."}
          </DialogDescription>
        </div>
        {!canShare ? (
          <p className="text-center text-[14px] text-muted">Sign in to share a list. Links need your account so they stay up to date.</p>
        ) : error ? (
          <p className="text-center text-[14px]">{error}</p>
        ) : (
          <>
            <p className="truncate rounded-xl bg-foreground/[0.06] px-3 py-2.5 text-center font-mono text-[12px] text-muted">{url || "Making the link…"}</p>
            <button
              type="button"
              disabled={!url}
              className={limeWide}
              onClick={async () => {
                await navigator.clipboard.writeText(url).catch(() => undefined);
                toast.success("Link copied");
              }}
            >
              <Copy className="mr-2 size-4" /> Copy link
            </button>
            {url && (
              <button
                type="button"
                className="h-11 text-[15px] font-semibold text-muted hover:text-foreground"
                onClick={() =>
                  stop().then(
                    () => {
                      toast("Link turned off");
                      onOpenChange(false);
                    },
                    (e: Error) => toast.error(e.message),
                  )
                }
              >
                Stop sharing
              </button>
            )}
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
