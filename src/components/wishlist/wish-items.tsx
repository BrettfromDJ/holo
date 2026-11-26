"use client";

import { Heart } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Hint } from "@/components/ui/tooltip";
import { useWishlist } from "@/lib/store/wishlist";
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
