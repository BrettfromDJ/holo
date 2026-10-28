"use client";

import { Copy, Heart, Link2 } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Field } from "@/components/flows/fields";
import { FormShell } from "@/components/flows/transaction-dialogs";
import { MetricStrip } from "@/components/overview/sections";
import { PageHeader } from "@/components/shell/page-header";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { WishTile } from "@/components/wishlist/wish-items";
import { money } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { hitTarget, sortWishes, useWishlist, useWishlistShare, type WishItem, type WishPriority } from "@/lib/store/wishlist";
import { priceKey } from "@/lib/types";

/** Latest saved price for a catalog product (no TCG API requests). */
async function catalogPrice(w: WishItem): Promise<number | null | undefined> {
  const res = await fetch(`/api/explore/products/${encodeURIComponent(w.product.id)}`);
  if (!res.ok) return undefined;
  const { prices } = (await res.json()) as { prices: { printing: string | null; market: number | null }[] };
  const match = prices.find((p) => p.printing === w.printing && p.market !== null) ?? prices.find((p) => p.market !== null);
  return match ? match.market : undefined;
}

export default function WishlistPage() {
  const store = useStore();
  const router = useRouter();
  const { items, ready, setPrices } = useWishlist();
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const [filter, setFilter] = useState<"all" | WishPriority>("all");
  const [shareOpen, setShareOpen] = useState(false);

  // Once per visit, bring each price up to date from saved prices.
  const [refreshed, setRefreshed] = useState(false);
  useEffect(() => {
    if (!ready || refreshed || store.status !== "ready") return;
    setRefreshed(true);
    void (async () => {
      const prices = new Map<string, number | null>();
      await Promise.all(
        items.map(async (w) => {
          const local = store.data.prices[priceKey(w.product.id, w.printing)];
          if (local && local.market !== null) return prices.set(w.product.id, local.market);
          if (w.product.id.startsWith("sample:")) return;
          const latest = await catalogPrice(w).catch(() => undefined);
          if (latest !== undefined) prices.set(w.product.id, latest);
        }),
      );
      if (prices.size) setPrices(prices);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once per visit, after the list loads
  }, [ready, refreshed, store.status]);

  const owned = useMemo(() => new Set(holdings.map((h) => h.identity.productId)), [holdings]);
  const sorted = useMemo(() => sortWishes(items), [items]);
  const shown = filter === "all" ? sorted : sorted.filter((w) => w.priority === filter);
  const toComplete = items.filter((w) => !owned.has(w.product.id)).reduce((s, w) => s + (w.price ?? 0), 0);
  const atTarget = items.filter(hitTarget).length;

  const bought = async (w: WishItem) => {
    // Load it into the collection's catalog, then open the purchase form.
    const known = Boolean(store.data.products[w.product.id]) || (await store.showCatalogProduct(w.product.id).catch(() => false));
    if (known) store.openAdd({ productId: w.product.id });
    else router.push(`/product/${encodeURIComponent(w.product.id)}`);
  };

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Wishlist"
        subtitle="Cards and sealed you want to own. Tap the heart on anything in Explore or on a product page."
        actions={
          items.length > 0 && (
            <Button variant="secondary" onClick={() => setShareOpen(true)}>
              <Link2 /> Share
            </Button>
          )
        }
      />

      {!ready ? (
        <div className="grid grid-cols-2 gap-5 sm:grid-cols-3 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="aspect-[5/7] rounded-2xl" />
          ))}
        </div>
      ) : !items.length ? (
        <div className="flex flex-col items-center rounded-[var(--radius-card)] border border-dashed border-border-strong px-6 py-20 text-center">
          <span className="flex size-12 items-center justify-center rounded-full bg-surface-2 ring-1 ring-border">
            <Heart className="size-5 text-muted" />
          </span>
          <p className="mt-4 font-medium">Your wishlist is empty</p>
          <p className="mt-1 max-w-sm text-[13px] text-muted">Tap the heart on any card or sealed product to save it here, with a priority and the price you&apos;d pay.</p>
          <Button variant="secondary" className="mt-5" asChild>
            <Link href="/explore">Browse Explore</Link>
          </Button>
        </div>
      ) : (
        <>
          <MetricStrip
            items={[
              { label: "To complete", value: money(toComplete), sub: "Market price of everything you don't own" },
              { label: "Items", value: String(items.length), sub: `${items.filter((w) => w.priority === "grail").length} grail${items.filter((w) => w.priority === "grail").length === 1 ? "" : "s"}` },
              { label: "At your target", value: atTarget ? <span className="text-up">{atTarget}</span> : "0", sub: atTarget ? "Good time to buy" : "Set targets to get flagged" },
              { label: "Already owned", value: String(items.filter((w) => owned.has(w.product.id)).length), sub: "In your collection" },
            ]}
          />

          <div className="mt-8 flex items-center justify-between gap-3">
            <Segmented
              ariaLabel="Priority"
              size="sm"
              value={filter}
              onChange={setFilter}
              options={[
                { value: "all", label: "All" },
                { value: "grail", label: "Grails" },
                { value: "want", label: "Want" },
                { value: "maybe", label: "Maybe" },
              ]}
            />
          </div>

          {shown.length ? (
            <div className="mt-6 grid grid-cols-2 gap-x-5 gap-y-10 sm:grid-cols-3 lg:grid-cols-4">
              {shown.map((w) => (
                <WishTile key={w.id} w={w} owned={owned.has(w.product.id)} onBought={() => void bought(w)} />
              ))}
            </div>
          ) : (
            <p className="py-16 text-center text-[14px] text-muted">Nothing marked {filter} yet.</p>
          )}
        </>
      )}

      <ShareDialog open={shareOpen} onOpenChange={setShareOpen} />
    </div>
  );
}

function ShareDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (o: boolean) => void }) {
  const { repoKind } = useStore();
  const { share, create, revoke } = useWishlistShare();
  const [title, setTitle] = useState("");
  useEffect(() => {
    if (open) setTitle(share?.title ?? "");
  }, [open, share?.title]);
  const url = share && typeof window !== "undefined" ? `${window.location.origin}/w/${share.token}` : "";
  const canShare = repoKind === "cloud";

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Share your wishlist"
          description="Anyone with the link sees your wishlist (names, prices and priorities), read-only. Handy for gifts and trades."
          onSubmit={(e) => {
            e.preventDefault();
            create(title.trim() || null);
            toast.success("Share link created");
          }}
          footer={
            !canShare ? (
              <p className="text-[13px] text-muted">Sign in to share your wishlist. Links need your account so they stay up to date.</p>
            ) : share ? (
              <Button
                type="button"
                variant="ghost"
                size="lg"
                className="w-full"
                onClick={() => {
                  revoke();
                  toast("Link turned off");
                }}
              >
                Turn off link
              </Button>
            ) : (
              <Button type="submit" variant="primary" size="lg" className="w-full">
                Create link
              </Button>
            )
          }
        >
          {canShare && !share && (
            <Field label="Title" htmlFor="wish-share-title" hint="Optional, shown at the top of the page">
              <Input id="wish-share-title" value={title} onChange={(e) => setTitle(e.target.value.slice(0, 80))} placeholder="e.g. Alex's wishlist" />
            </Field>
          )}
          {canShare && share && (
            <div className="flex items-center gap-2">
              <Input readOnly value={url} aria-label="Share link" onFocus={(e) => e.target.select()} />
              <Button
                type="button"
                variant="secondary"
                onClick={async () => {
                  await navigator.clipboard.writeText(url).catch(() => undefined);
                  toast.success("Link copied");
                }}
              >
                <Copy /> Copy
              </Button>
            </div>
          )}
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}
