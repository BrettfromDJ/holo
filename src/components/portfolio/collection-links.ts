import type { HoldingCategory, HoldingView } from "@/lib/finance/portfolio";

/** Collection's chips: Singles, Sealed, Graded (no All tab, as in the app). */
export type CollectionCategory = "singles" | "sealed" | "graded";
export type CollectionSort = "value" | "gain" | "gainPct" | "move" | "date" | "name";

export const CATEGORY_OF: Record<CollectionCategory, HoldingCategory> = { singles: "single", sealed: "sealed", graded: "graded" };
export const CHIP_OF: Record<HoldingCategory, CollectionCategory> = { single: "singles", sealed: "sealed", graded: "graded" };

/** A link into Collection's Cards: `cat` (a chip), `list` (a list's id) and `sort`. */
export function collectionHref(opts: { cat?: CollectionCategory | HoldingCategory; list?: string; sort?: CollectionSort; summary?: boolean } = {}): string {
  const q = new URLSearchParams();
  if (opts.summary) q.set("view", "summary");
  if (opts.cat) q.set("cat", opts.cat in CHIP_OF ? CHIP_OF[opts.cat as HoldingCategory] : opts.cat);
  if (opts.list) q.set("list", opts.list);
  if (opts.sort && opts.sort !== "value") q.set("sort", opts.sort);
  const s = q.toString();
  return s ? `/collection?${s}` : "/collection";
}

/** A card's page, on the copy's printing (tapping a card opens its page everywhere). */
export function cardHref(h: HoldingView): string {
  const base = `/product/${encodeURIComponent(h.identity.productId)}`;
  return h.identity.printing ? `${base}?printing=${encodeURIComponent(h.identity.printing)}` : base;
}
