"use client";

import { useCallback, useMemo } from "react";
import type { Product } from "../types";
import type { WishItem, WishlistShare, WishPriority } from "../wishlist";

export { hitTarget, PRIORITIES, sortWishes, type WishItem, type WishlistShare, type WishPriority } from "../wishlist";
import { useSyncedState } from "./synced-state";

/**
 * Products you want to own. Separate from the Watchlist (price tracking):
 * each has a priority and an optional target price. Synced to the account
 * when signed in.
 */
export function useWishlist() {
  const [items, setItems, ready] = useSyncedState<WishItem[]>("wishlist", []);
  const ids = useMemo(() => new Set(items.map((w) => w.product.id)), [items]);

  const add = useCallback(
    (product: Product, price: number | null, opts?: { printing?: string | null; priority?: WishPriority }) =>
      setItems((prev) =>
        prev.some((w) => w.product.id === product.id)
          ? prev
          : [...prev, { id: crypto.randomUUID(), product, printing: opts?.printing ?? null, priority: opts?.priority ?? "want", target: null, price, addedAt: new Date().toISOString() }],
      ),
    [setItems],
  );
  const update = useCallback((id: string, patch: Partial<Pick<WishItem, "priority" | "target" | "price">>) => setItems((prev) => prev.map((w) => (w.id === id ? { ...w, ...patch } : w))), [setItems]);
  const remove = useCallback((productId: string) => setItems((prev) => prev.filter((w) => w.product.id !== productId)), [setItems]);
  const setPrices = useCallback(
    (prices: Map<string, number | null>) => setItems((prev) => prev.map((w) => (prices.has(w.product.id) && prices.get(w.product.id) !== undefined ? { ...w, price: prices.get(w.product.id) ?? w.price } : w))),
    [setItems],
  );

  return { items, ready, ids, has: (productId: string) => ids.has(productId), add, update, remove, setPrices };
}

export function useWishlistShare() {
  // Stored as `{ token: null }` when off: account values can't be null.
  const [stored, setStored] = useSyncedState<WishlistShare | { token: null; title: null }>("wishlist-share", { token: null, title: null });
  const share = stored.token ? (stored as WishlistShare) : null;
  const create = useCallback(
    (title: string | null) => {
      const bytes = crypto.getRandomValues(new Uint8Array(18));
      const token = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
      setStored({ token, title });
    },
    [setStored],
  );
  const revoke = useCallback(() => setStored({ token: null, title: null }), [setStored]);
  return { share, create, revoke };
}
