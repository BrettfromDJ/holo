import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ProductImage } from "@/components/product/product-image";
import { Logo } from "@/components/shell/logo";
import { todayISO } from "@/lib/finance/dates";
import { computeHoldings, type HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money } from "@/lib/format";
import { askingPrice, LIST_META_KEY, listIdFromShareTitle, parseListMeta } from "@/lib/lists";
import { loadCollection } from "@/lib/supabase/load";
import { priceFromRow, productFromRow } from "@/lib/supabase/mappers";
import { getAdminSupabase } from "@/lib/supabase/server";
import type { Product } from "@/lib/types";

export const dynamic = "force-dynamic";

interface Item {
  product: Product;
  /** Your copy's condition or grade, when you own it. */
  copy: string | null;
  grade: HoldingView["identity"]["grade"];
  quantity: number;
  market: number | null;
  asking: number | null;
}

/**
 * Public, read-only page for one list (a card show's "for sale" list, or favorites), behind an
 * unguessable share token. Rendered on the server with the service role. Shows each card's
 * picture, name, set, condition or grade, market price and, on a list for sale, the asking
 * price. Never what anything cost, notes, sources, email, or the rest of the collection.
 */
async function loadList(token: string) {
  const admin = getAdminSupabase();
  if (!admin || !/^[A-Za-z0-9_-]{20,64}$/.test(token)) return null;
  const { data: link } = await admin.from("share_links").select("*").eq("token", token).is("revoked_at", null).maybeSingle();
  const listId = listIdFromShareTitle(link?.title);
  if (!link || !listId) return null;
  const { data: list } = await admin.from("shelves").select("*").eq("id", listId).eq("user_id", link.user_id).maybeSingle();
  if (!list) return null;
  const { data: state } = await admin.from("user_state").select("value").eq("user_id", link.user_id).eq("key", LIST_META_KEY).maybeSingle();
  const meta = parseListMeta(state?.value)[listId];
  const forSale = meta?.forSale === true;

  const today = todayISO();
  const data = await loadCollection(admin, link.user_id);
  const holdings = computeHoldings(data, today);
  const ids: string[] = list.product_ids ?? [];

  // Products on the list you don't own: their details and market prices.
  const missing = ids.filter((id) => !data.products[id]);
  const extraPrices = new Map<string, number>();
  if (missing.length) {
    const [{ data: rows }, { data: priceRows }] = await Promise.all([
      admin.from("products").select("*").in("id", missing),
      admin.from("product_prices").select("*").in("product_id", missing),
    ]);
    for (const r of rows ?? []) data.products[r.id] = productFromRow(r);
    for (const r of priceRows ?? []) {
      const p = priceFromRow(r);
      if (p.market != null) extraPrices.set(p.productId, Math.max(extraPrices.get(p.productId) ?? 0, p.market));
    }
  }

  const items: Item[] = [];
  for (const id of ids) {
    const product = data.products[id];
    if (!product) continue;
    // Your most valuable copy stands for the card.
    const copies = holdings.filter((h) => h.identity.productId === id && h.quantity > 0).sort((a, b) => (b.price ?? -1) - (a.price ?? -1));
    const top = copies[0];
    const market = top?.price ?? extraPrices.get(id) ?? null;
    items.push({
      product,
      copy: top ? (top.identity.grade ? `${top.identity.grade.company} ${top.identity.grade.grade}` : top.identity.condition) : null,
      grade: top?.identity.grade ?? null,
      quantity: copies.reduce((n, h) => n + h.quantity, 0),
      market,
      asking: forSale ? askingPrice(meta, id, market) : null,
    });
  }
  const marketTotal = items.reduce((n, i) => n + (i.market ?? 0) * Math.max(1, i.quantity), 0);
  const askingTotal = items.reduce((n, i) => n + (i.asking ?? 0) * Math.max(1, i.quantity), 0);
  return { name: list.name as string, forSale, items, marketTotal, askingTotal, today };
}

export async function generateMetadata({ params }: { params: Promise<{ token: string }> }): Promise<Metadata> {
  const { token } = await params;
  const list = await loadList(token);
  return { title: list?.name || "Shared list", robots: { index: false, follow: false } };
}

export default async function SharedListPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const list = await loadList(token);
  if (!list) notFound();
  const { name, forSale, items, marketTotal, askingTotal, today } = list;
  const count = items.reduce((n, i) => n + Math.max(1, i.quantity), 0);

  return (
    <main className="mx-auto w-full max-w-[1100px] px-4 pb-24 pt-8 sm:px-8 sm:pt-12">
      <div className="flex items-center justify-between">
        <Logo />
        <span className={`rounded-full px-3 py-1 text-[12px] font-semibold ${forSale ? "bg-lime text-[#0b0b0c]" : "bg-surface-2 text-muted"}`}>
          {forSale ? "For sale" : "List"}
        </span>
      </div>

      <header className="mt-12">
        <h1 className="font-display text-[34px] leading-tight tracking-tight sm:text-[44px]">{name}</h1>
        <p className="tabular mt-4 font-display text-[42px] leading-none text-lime sm:text-[58px]">{money(forSale ? askingTotal : marketTotal)}</p>
        <p className="mt-3 text-[14px] text-muted">
          {count} card{count === 1 ? "" : "s"}
          {forSale ? ` · asking, against ${money(marketTotal)} market` : " · market value"}
        </p>
      </header>

      <section className="mt-10">
        {items.length ? (
          <div className="grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-4">
            {items.map((i) => (
              <div key={i.product.id} className="flex flex-col">
                <div className="relative">
                  <ProductImage product={i.product} grade={i.grade} className="aspect-square w-full" />
                  {i.quantity > 1 && (
                    <span className="tabular absolute left-2.5 top-2.5 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-semibold backdrop-blur">×{i.quantity}</span>
                  )}
                </div>
                <p className="mt-3 truncate text-[14px] font-medium">{i.product.name}</p>
                <p className="truncate text-[12px] text-muted">{[i.product.setName, i.product.number, i.copy].filter(Boolean).join(" · ")}</p>
                <div className="mt-2 flex items-end justify-between gap-2">
                  <p className={`tabular text-[17px] font-semibold ${forSale ? "text-lime" : ""}`}>{money(forSale ? i.asking : i.market)}</p>
                  {forSale && <p className="tabular text-[12px] text-muted">market {money(i.market)}</p>}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="py-16 text-center text-[15px] text-muted">This list is empty.</p>
        )}
      </section>

      <footer className="mt-16 border-t border-border pt-6 text-[12px] text-subtle">
        {forSale ? "Asking prices are set by the seller. " : ""}Market prices as of {formatDate(today)}. Shared with Dexora.
      </footer>
    </main>
  );
}
