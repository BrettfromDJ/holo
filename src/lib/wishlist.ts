import type { Product } from "./types";

export type WishPriority = "grail" | "want" | "maybe";

export const PRIORITIES: { value: WishPriority; label: string }[] = [
  { value: "grail", label: "Grail" },
  { value: "want", label: "Want" },
  { value: "maybe", label: "Maybe" },
];

export interface WishItem {
  id: string;
  /** A copy of the product, so the list shows even for products not in the collection. */
  product: Product;
  printing: string | null;
  priority: WishPriority;
  /** Price you'd happily pay. */
  target: number | null;
  /** Latest known market price, refreshed when the wishlist is opened. */
  price: number | null;
  addedAt: string;
}

const RANK: Record<WishPriority, number> = { grail: 0, want: 1, maybe: 2 };

export function sortWishes(items: WishItem[]): WishItem[] {
  return [...items].sort((a, b) => RANK[a.priority] - RANK[b.priority] || (b.price ?? 0) - (a.price ?? 0));
}

/** At or below the price you set. */
export function hitTarget(w: Pick<WishItem, "price" | "target">): boolean {
  return w.price !== null && w.target !== null && w.price <= w.target;
}

/** The share token for a public, read-only wishlist page; stored with the account. */
export interface WishlistShare {
  token: string;
  title: string | null;
}

