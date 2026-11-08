/**
 * Lists (stored in the `shelves` table; the app called them shelves before). A list is a named
 * set of products, owned or not: favorites, want lists, or cards to sell at a show. The extras a
 * list can have live in user_state `list-meta`, keyed by list id, so no new columns are needed.
 * Same rules as the app's `Domain/ListPricing.swift`.
 */
export interface ListMeta {
  /** Selling these: show asking prices and totals. */
  forSale?: boolean;
  /** Asking price as a share of market, e.g. 90 for 90%. Missing means 100%. */
  askPercent?: number | null;
  /** Asking prices set by hand, by product id. They win over any percentage. */
  prices?: Record<string, number>;
  /** A percentage of market for one card, by product id. Wins over the list's percentage. */
  percents?: Record<string, number>;
}

export type ListMetaMap = Record<string, ListMeta>;

export const LIST_META_KEY = "list-meta";
/** A share link for one list carries this title prefix (then the list id). */
export const LIST_SHARE_PREFIX = "list:";

export function listShareTitle(listId: string): string {
  return `${LIST_SHARE_PREFIX}${listId}`;
}

export function listIdFromShareTitle(title: string | null | undefined): string | null {
  return title && title.startsWith(LIST_SHARE_PREFIX) ? title.slice(LIST_SHARE_PREFIX.length) || null : null;
}

/** What you're asking for one copy: your own price, else market × the card's percentage, else × the list's. */
export function askingPrice(meta: ListMeta | undefined, productId: string, market: number | null): number | null {
  const own = meta?.prices?.[productId];
  if (own != null && Number.isFinite(own) && own >= 0) return own;
  if (market == null) return null;
  const pct = meta?.percents?.[productId] ?? meta?.askPercent ?? 100;
  return Math.round(market * pct) / 100;
}

/** Read whatever was stored, dropping anything malformed. */
export function parseListMeta(value: unknown): ListMetaMap {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const out: ListMetaMap = {};
  for (const [id, raw] of Object.entries(value as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object") continue;
    const r = raw as Record<string, unknown>;
    const prices: Record<string, number> = {};
    if (r.prices && typeof r.prices === "object") {
      for (const [pid, v] of Object.entries(r.prices as Record<string, unknown>)) if (typeof v === "number" && v >= 0) prices[pid] = v;
    }
    const percents: Record<string, number> = {};
    if (r.percents && typeof r.percents === "object") {
      for (const [pid, v] of Object.entries(r.percents as Record<string, unknown>)) if (validPercent(v)) percents[pid] = v;
    }
    out[id] = {
      forSale: r.forSale === true,
      askPercent: validPercent(r.askPercent) ? r.askPercent : null,
      prices,
      percents,
    };
  }
  return out;
}

function validPercent(v: unknown): v is number {
  return typeof v === "number" && v > 0 && v <= 200;
}
