"use client";

import { Check, Diff, Eye, EyeOff, Folder, Heart, HeartOff, Library, MoreHorizontal, Plus, Share, Tag } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { SellCalculatorDialog } from "@/components/flows/sell-calculator";
import { SaleDialog } from "@/components/flows/transaction-dialogs";
import { holdingLabel } from "@/components/portfolio/holding-items";
import { ShelfDialog } from "@/components/shelves/shelf-controls";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import type { HoldingView } from "@/lib/finance/portfolio";
import { useStore } from "@/lib/store/collection-store";
import { MAIN, MAIN_NAME, usePortfolios } from "@/lib/store/portfolios";
import { useShelves } from "@/lib/store/shelves";
import { useWishlist } from "@/lib/store/wishlist";
import type { Product } from "@/lib/types";
import { MenuSub, MenuSubContent, MenuSubTrigger } from "./menu-sub";

/** The round glass ⋯ button's look, shared with the copy rows' and Your copy's ⋯. */
export const glassRound = "flex size-10 shrink-0 items-center justify-center rounded-full border border-white/10 bg-white/[0.06] text-white backdrop-blur-xl transition-colors hover:bg-white/[0.1] data-[state=open]:bg-white/[0.12]";

const run = (work: Promise<unknown>, done?: string) =>
  work.then(
    () => done && toast(done),
    (e: Error) => toast.error(e.message),
  );

/**
 * Everything you can do with this card, in one ⋯ menu at the top right of the card page (the
 * app's moreActions): add, sell or try a sale, watch, wishlist, lists, portfolio, share.
 */
export function PageActions({ product, printing, price, owned }: { product: Product; printing: string | null; price: number | null; owned: HoldingView[] }) {
  const store = useStore();
  const wishlist = useWishlist();
  const { shelves, toggle } = useShelves();
  const { portfolios, membersOf, moveMany } = usePortfolios();
  const [dialog, setDialog] = useState<{ kind: "sale" | "whatif"; key: string } | null>(null);
  const [creating, setCreating] = useState(false);
  const target = owned.find((h) => h.key === dialog?.key) ?? null;
  const watch = store.data.watchlist.find((w) => w.productId === product.id);
  const wished = wishlist.has(product.id);
  // Radix closes the menu first; a dialog opened in the same tick loses its focus trap.
  const later = (f: () => void) => window.setTimeout(f, 0);

  const copyAction = (kind: "sale" | "whatif", label: string, icon: React.ReactNode) =>
    owned.length === 1 ? (
      <DropdownMenuItem onSelect={() => later(() => setDialog({ kind, key: owned[0].key }))}>
        {icon} {label}
      </DropdownMenuItem>
    ) : (
      <MenuSub>
        <MenuSubTrigger>
          {icon} {label}
        </MenuSubTrigger>
        <MenuSubContent>
          {owned.map((h) => (
            <DropdownMenuItem key={h.key} onSelect={() => later(() => setDialog({ kind, key: h.key }))}>
              <span className="flex-1 truncate">{holdingLabel(h) ?? (product.kind === "sealed" ? "Sealed" : h.identity.condition)}</span>
              <span className="tabular text-muted">×{h.quantity}</span>
            </DropdownMenuItem>
          ))}
        </MenuSubContent>
      </MenuSub>
    );

  const inPortfolios = new Set(owned.flatMap((h) => membersOf(h.key)));
  const share = async () => {
    const url = window.location.href;
    try {
      if (navigator.share) await navigator.share({ title: product.name, url });
      else {
        await navigator.clipboard.writeText(url);
        toast("Link copied");
      }
    } catch {
      // Closing the share sheet isn't an error.
    }
  };

  return (
    <>
      <DropdownMenu modal={false}>
        <DropdownMenuTrigger aria-label="More actions" className={glassRound}>
          <MoreHorizontal className="size-[18px]" />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-64">
          <DropdownMenuItem onSelect={() => store.openAdd({ productId: product.id })}>
            <Plus /> {owned.length ? "Add more" : "Add to collection"}
          </DropdownMenuItem>
          {owned.length > 0 && (
            <>
              <DropdownMenuSeparator />
              {copyAction("sale", "Record sale", <Tag />)}
              {copyAction("whatif", "What if I sell?", <Diff />)}
            </>
          )}
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onSelect={() =>
              void (watch ? run(store.removeWatch(watch.id), "Removed from your watchlist") : run(store.addWatch(product.id, printing, null), "Added to your watchlist"))
            }
          >
            {watch ? <EyeOff /> : <Eye />} {watch ? "Stop watching" : "Watch price"}
          </DropdownMenuItem>
          <DropdownMenuItem
            onSelect={() => {
              if (wished) {
                wishlist.remove(product.id);
                toast("Removed from your wishlist");
              } else {
                wishlist.add(product, price, { printing });
                toast("Added to your wishlist");
              }
            }}
          >
            {wished ? <HeartOff /> : <Heart />} {wished ? "Remove from wishlist" : "Add to wishlist"}
          </DropdownMenuItem>
          <MenuSub>
            <MenuSubTrigger>
              <Library /> Lists
            </MenuSubTrigger>
            <MenuSubContent>
              {shelves.map((s) => {
                const on = s.productIds.includes(product.id);
                return (
                  <DropdownMenuItem
                    key={s.id}
                    onSelect={(e) => {
                      e.preventDefault();
                      void run(toggle(s.id, product.id), on ? `Removed from ${s.name}` : `Added to ${s.name}`);
                    }}
                  >
                    <span className="flex-1 truncate">{s.name}</span>
                    {on && <Check className="!text-foreground" />}
                  </DropdownMenuItem>
                );
              })}
              {shelves.length > 0 && <DropdownMenuSeparator />}
              <DropdownMenuItem onSelect={() => later(() => setCreating(true))}>
                <Plus /> New list…
              </DropdownMenuItem>
            </MenuSubContent>
          </MenuSub>
          {owned.length > 0 && portfolios.length > 0 && (
            <MenuSub>
              <MenuSubTrigger>
                <Folder /> Portfolio
              </MenuSubTrigger>
              <MenuSubContent>
                {/* A check on every portfolio your copies show in; picking one moves them there. */}
                {[{ id: MAIN, name: MAIN_NAME }, ...portfolios].map((p) => (
                  <DropdownMenuItem key={p.id} onSelect={() => void run(moveMany(owned.map((h) => h.key), p.id), `Moved to ${p.name}`)}>
                    <span className="flex-1 truncate">{p.name}</span>
                    {inPortfolios.has(p.id) && <Check className="!text-foreground" />}
                  </DropdownMenuItem>
                ))}
              </MenuSubContent>
            </MenuSub>
          )}
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => void share()}>
            <Share /> Share
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      {target && <SaleDialog holding={target} open={dialog?.kind === "sale"} onOpenChange={(o) => !o && setDialog(null)} />}
      {target && <SellCalculatorDialog holding={target} open={dialog?.kind === "whatif"} onOpenChange={(o) => !o && setDialog(null)} />}
      <ShelfDialog open={creating} onOpenChange={setCreating} initialProductIds={[product.id]} />
    </>
  );
}
