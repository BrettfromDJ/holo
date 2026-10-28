import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ProductImage } from "@/components/product/product-image";
import { Logo } from "@/components/shell/logo";
import { categoryOf } from "@/lib/catalog";
import { money } from "@/lib/format";
import { sortWishes, type WishItem, type WishPriority } from "@/lib/wishlist";
import { getAdminSupabase } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";

export const dynamic = "force-dynamic";

const LABEL: Record<WishPriority, string> = { grail: "Grail", want: "Want", maybe: "Maybe" };

/**
 * Public, read-only wishlist behind an unguessable token. The token lives in
 * the owner's `user_state` ("wishlist-share"); turning the link off clears it.
 * Only product names, images, prices and priorities are shown. No email,
 * collection or targets.
 */
async function loadWishlist(token: string) {
  const admin = getAdminSupabase();
  if (!admin || !/^[A-Za-z0-9_-]{20,64}$/.test(token)) return null;
  const { data: link } = await admin.from("user_state").select("user_id, value").eq("key", "wishlist-share").eq("value->>token", token).maybeSingle();
  if (!link) return null;
  const { data: list } = await admin.from("user_state").select("value").eq("user_id", link.user_id).eq("key", "wishlist").maybeSingle();
  const items = sortWishes(((list?.value as unknown as WishItem[] | null) ?? []).filter((w) => w?.product?.id));
  // Freshest saved market price for each item.
  const ids = items.map((w) => w.product.id);
  const { data: prices } = ids.length ? await admin.from("product_prices").select("product_id, printing, market_price").in("product_id", ids) : { data: [] };
  const latest = new Map<string, number>();
  for (const p of prices ?? []) if (p.market_price !== null && !latest.has(p.product_id)) latest.set(p.product_id, Number(p.market_price));
  return {
    title: (link.value as { title?: string | null }).title ?? null,
    items: items.map((w) => ({ ...w, price: latest.get(w.product.id) ?? w.price })),
  };
}

export async function generateMetadata({ params }: { params: Promise<{ token: string }> }): Promise<Metadata> {
  const { token } = await params;
  const list = await loadWishlist(token);
  return { title: list?.title || "Wishlist", robots: { index: false, follow: false } };
}

export default async function SharedWishlistPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const list = await loadWishlist(token);
  if (!list) notFound();
  const total = list.items.reduce((s, w) => s + (w.price ?? 0), 0);

  return (
    <main className="mx-auto w-full max-w-[1100px] px-4 pb-24 pt-8 sm:px-8 sm:pt-12">
      <div className="flex items-center justify-between">
        <Logo />
        <span className="rounded-full bg-surface-2 px-3 py-1 text-[12px] text-muted">Wishlist · read-only</span>
      </div>

      <header className="mt-12">
        <p className="text-[14px] font-medium text-muted">{list.title || "Wishlist"}</p>
        <p className="tabular mt-2 text-[44px] font-semibold leading-none tracking-[-0.035em] sm:text-[56px]">{money(total)}</p>
        <p className="mt-3 text-[14px] text-muted">
          {list.items.length} item{list.items.length === 1 ? "" : "s"} · at today&apos;s market prices
        </p>
      </header>

      {list.items.length ? (
        <div className="mt-10 grid grid-cols-2 gap-x-5 gap-y-10 sm:grid-cols-3 lg:grid-cols-4">
          {list.items.map((w) => (
            <div key={w.id} className="relative min-w-0">
              <ProductImage product={w.product} size="lg" frame={w.product.kind !== "single"} className="aspect-[5/7] w-full items-end" />
              <span className={cn("absolute left-2 top-2 rounded-full px-2 py-0.5 font-mono text-[10px] font-medium uppercase tracking-[0.06em] ring-1", w.priority === "grail" ? "bg-foreground text-background ring-foreground" : "bg-background/80 text-foreground/80 ring-border")}>
                {LABEL[w.priority]}
              </span>
              <p className="mt-3 line-clamp-2 text-[14px] font-medium leading-snug">{w.product.name}</p>
              <p className="truncate text-[12px] text-muted">{[w.product.setName, w.product.kind === "sealed" ? categoryOf(w.product) : w.product.number ? `#${w.product.number}` : null].filter(Boolean).join(" · ")}</p>
              <p className="tabular mt-1.5 text-[16px] font-semibold">{w.price === null ? <span className="text-[14px] font-normal text-subtle">No price</span> : money(w.price)}</p>
            </div>
          ))}
        </div>
      ) : (
        <p className="mt-16 text-center text-[14px] text-muted">Nothing on this wishlist yet.</p>
      )}
    </main>
  );
}
