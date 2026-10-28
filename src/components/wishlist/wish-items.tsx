"use client";

import { useHeroLink } from "@/lib/motion/hero";
import { Check, Heart, MoreHorizontal } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Field, MoneyInput, parseMoney } from "@/components/flows/fields";
import { FormShell } from "@/components/flows/transaction-dialogs";
import { ProductImage } from "@/components/product/product-image";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Hint } from "@/components/ui/tooltip";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { categoryOf } from "@/lib/catalog";
import { money } from "@/lib/format";
import { hitTarget, PRIORITIES, useWishlist, type WishItem, type WishPriority } from "@/lib/store/wishlist";
import type { Product } from "@/lib/types";
import { cn } from "@/lib/utils";

/** Heart toggle: add or remove a product from the wishlist. `compact` shows just the heart, labelled on hover. */
export function WishButton({ product, price, printing, className, compact }: { product: Product; price: number | null; printing?: string | null; className?: string; compact?: boolean }) {
  const { has, add, remove } = useWishlist();
  const on = has(product.id);
  const [burst, setBurst] = useState(0);
  const toggle = () => {
    if (on) {
      remove(product.id);
      toast("Removed from wishlist");
    } else {
      add(product, price, { printing });
      setBurst((n) => n + 1);
      toast.success("Added to wishlist");
    }
  };
  if (compact) {
    return (
      <Hint content={on ? "On wishlist · tap to remove" : "Add to wishlist"}>
        <Button variant="secondary" size="icon" aria-label={on ? "Remove from wishlist" : "Add to wishlist"} aria-pressed={on} className={cn("relative", className)} onClick={toggle}>
          <HeartBurst on={on} burst={burst} />
        </Button>
      </Hint>
    );
  }
  return (
    <Button variant="secondary" className={cn("relative", className)} onClick={toggle}>
      <span className="relative inline-flex">
        <HeartBurst on={on} burst={burst} />
      </span>
      {on ? "On wishlist" : "Wishlist"}
    </Button>
  );
}

/** A small heart over a tile; stops the tile's link from opening. */
export function WishHeart({ product, price, printing, className }: { product: Product; price: number | null; printing?: string | null; className?: string }) {
  const { has, add, remove } = useWishlist();
  const on = has(product.id);
  const [burst, setBurst] = useState(0);
  return (
    <button
      type="button"
      aria-label={on ? "Remove from wishlist" : "Add to wishlist"}
      aria-pressed={on}
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        if (on) remove(product.id);
        else {
          add(product, price, { printing });
          setBurst((n) => n + 1);
          toast.success("Added to wishlist");
        }
      }}
      className={cn(
        "relative flex size-8 items-center justify-center rounded-full bg-background/80 ring-1 ring-border backdrop-blur transition-all hover:scale-110",
        on ? "text-foreground opacity-100" : "text-muted opacity-0 group-hover:opacity-100 focus-visible:opacity-100 max-sm:opacity-100",
        className,
      )}
    >
      <HeartBurst on={on} burst={burst} className="size-4" />
    </button>
  );
}

/** The heart icon; each new `burst` replays a pop and a ring spreading out. */
function HeartBurst({ on, burst, className }: { on: boolean; burst: number; className?: string }) {
  return (
    <>
      <Heart key={burst} className={cn(className, on && "fill-current", burst > 0 && "heart-pop")} />
      {burst > 0 && <span key={`ring-${burst}`} aria-hidden className="heart-ring" />}
    </>
  );
}

const PRIORITY_LABEL: Record<WishPriority, string> = { grail: "Grail", want: "Want", maybe: "Maybe" };

/** A wishlist entry: big card image, priority, price against your target. */
export function WishTile({ w, owned, onBought }: { w: WishItem; owned: boolean; onBought: () => void }) {
  const hero = useHeroLink();
  const { update, remove } = useWishlist();
  const [targetOpen, setTargetOpen] = useState(false);
  const p = w.product;
  const hit = hitTarget(w);
  return (
    <div className="group relative flex min-w-0 flex-col">
      <Link href={`/product/${encodeURIComponent(p.id)}`} onClick={(e) => hero(e, `/product/${encodeURIComponent(p.id)}`)} className="block">
        <ProductImage product={p} size="lg" frame={p.kind !== "single"} className="aspect-[5/7] w-full items-end transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1" />
      </Link>
      <div className="pointer-events-none absolute left-2 top-2 flex flex-wrap gap-1.5">
        <span className={cn("rounded-full px-2 py-0.5 font-mono text-[10px] font-medium uppercase tracking-[0.06em] ring-1 backdrop-blur", w.priority === "grail" ? "bg-foreground text-background ring-foreground" : "bg-background/80 text-foreground/80 ring-border")}>
          {PRIORITY_LABEL[w.priority]}
        </span>
        {owned && (
          <span className="flex items-center gap-1 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-medium ring-1 ring-border backdrop-blur">
            <Check className="size-3" /> Owned
          </span>
        )}
      </div>

      <div className="mt-3 flex items-start justify-between gap-2">
        <Link href={`/product/${encodeURIComponent(p.id)}`} className="min-w-0">
          <p className="line-clamp-2 text-[14px] font-medium leading-snug">{p.name}</p>
          <p className="truncate text-[12px] text-muted">{[p.setName, p.kind === "sealed" ? categoryOf(p) : p.number ? `#${p.number}` : null].filter(Boolean).join(" · ")}</p>
        </Link>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon-sm" aria-label="Wishlist actions" className="-mr-1.5 shrink-0">
              <MoreHorizontal />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuLabel>Priority</DropdownMenuLabel>
            <DropdownMenuRadioGroup value={w.priority} onValueChange={(v) => update(w.id, { priority: v as WishPriority })}>
              {PRIORITIES.map((o) => (
                <DropdownMenuRadioItem key={o.value} value={o.value}>
                  {o.label}
                </DropdownMenuRadioItem>
              ))}
            </DropdownMenuRadioGroup>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={() => setTargetOpen(true)}>{w.target === null ? "Set target price" : "Change target price"}</DropdownMenuItem>
            <DropdownMenuItem onSelect={onBought}>I bought it</DropdownMenuItem>
            <DropdownMenuItem
              onSelect={() => {
                remove(p.id);
                toast("Removed from wishlist");
              }}
            >
              Remove
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <div className="mt-1.5 flex items-baseline justify-between gap-2">
        <p className="tabular text-[16px] font-semibold">{w.price === null ? <span className="text-[14px] font-normal text-subtle">No price</span> : money(w.price)}</p>
        {w.target !== null ? (
          <p className="tabular text-[12px] text-muted">
            {hit ? (
              <>
                <span className="text-up">At target</span> · {money(w.target)}
              </>
            ) : (
              <>Target {money(w.target)}</>
            )}
          </p>
        ) : (
          <button type="button" onClick={() => setTargetOpen(true)} className="text-[12px] text-subtle hover:text-foreground">
            Set target
          </button>
        )}
      </div>
      <TargetDialog item={w} open={targetOpen} onOpenChange={setTargetOpen} />
    </div>
  );
}

function TargetDialog({ item, open, onOpenChange }: { item: WishItem; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { update } = useWishlist();
  const [value, setValue] = useState("");
  useEffect(() => {
    if (open) setValue(item.target !== null ? item.target.toFixed(2) : "");
  }, [open, item.target]);
  const v = parseMoney(value);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Target price"
          description={`What you'd happily pay for ${item.product.name}. It's flagged when the market price reaches it.`}
          onSubmit={(e) => {
            e.preventDefault();
            update(item.id, { target: v });
            toast.success(v === null ? "Target removed" : "Target saved");
            onOpenChange(false);
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full">
              {v === null && item.target !== null ? "Remove target" : "Save"}
            </Button>
          }
        >
          <Field label="Target price" htmlFor="wish-target" hint={item.price !== null ? `Market price now ${money(item.price)}` : undefined}>
            <MoneyInput id="wish-target" value={value} onChange={setValue} autoFocus />
          </Field>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}
