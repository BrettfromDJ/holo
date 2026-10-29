import type { ConditionPrice, EbaySales, EbaySummary } from "./ebay-types";

/**
 * Loads a card's eBay sales from the app's route (which caches upstream for
 * 12 hours), and keeps results on this device for 12 hours too, so revisits
 * and the collection's slab values don't spend TCG API credits again.
 */

const TTL = 12 * 60 * 60 * 1000;
const memory = new Map<string, { at: number; value: EbaySales | null }>();
const inflight = new Map<string, Promise<EbaySales | null>>();

const keyOf = (productId: string, printing: string | null) => `${productId}:${printing ?? ""}`;

export function cachedEbay(productId: string, printing: string | null): { value: EbaySales | null } | null {
  const key = keyOf(productId, printing);
  const hit = memory.get(key);
  if (hit && Date.now() - hit.at < TTL) return hit;
  try {
    const raw = localStorage.getItem(`holo:ebay:${key}`);
    const v = raw ? (JSON.parse(raw) as { at: number; value: EbaySales | null }) : null;
    if (v && Date.now() - v.at < TTL) {
      memory.set(key, v);
      return v;
    }
  } catch {
    /* storage unavailable */
  }
  return null;
}

function remember(productId: string, printing: string | null, value: EbaySales | null) {
  const v = { at: Date.now(), value };
  memory.set(keyOf(productId, printing), v);
  try {
    localStorage.setItem(`holo:ebay:${keyOf(productId, printing)}`, JSON.stringify(v));
  } catch {
    /* storage full or unavailable */
  }
}

export class EbayLoadError extends Error {
  constructor(
    message: string,
    public readonly tier: boolean,
  ) {
    super(message);
  }
}

/** A card's eBay sales, from this device's cache or the server. One request per card at a time. */
export function loadEbay(productId: string, printing: string | null): Promise<EbaySales | null> {
  const hit = cachedEbay(productId, printing);
  if (hit) return Promise.resolve(hit.value);
  const key = keyOf(productId, printing);
  const pending = inflight.get(key);
  if (pending) return pending;
  const p = fetch(`/api/tcg/products/${encodeURIComponent(productId)}/ebay${printing ? `?printing=${encodeURIComponent(printing)}` : ""}`)
    .then(async (r) => {
      const body = await r.json().catch(() => null);
      if (!r.ok) throw new EbayLoadError(body?.error?.message ?? "Couldn't load eBay sales.", body?.error?.code === "tier");
      const value = (body?.ebay ?? null) as EbaySales | null;
      remember(productId, printing, value);
      return value;
    })
    .finally(() => inflight.delete(key));
  inflight.set(key, p);
  return p;
}

/* ------------------------- Summaries and conditions ------------------------ */

function readStored<T>(key: string): T | undefined {
  try {
    const raw = localStorage.getItem(key);
    const v = raw ? (JSON.parse(raw) as { at: number; value: T }) : null;
    return v && Date.now() - v.at < TTL ? v.value : undefined;
  } catch {
    return undefined;
  }
}

function store<T>(key: string, value: T) {
  try {
    localStorage.setItem(key, JSON.stringify({ at: Date.now(), value }));
  } catch {
    /* storage full or unavailable */
  }
}

/**
 * eBay summaries (no listings) for many cards, one bulk request for the ones
 * not already on this device. Cards without eBay data come back as [].
 */
export async function loadSummaries(productIds: string[]): Promise<Record<string, EbaySummary[]>> {
  const out: Record<string, EbaySummary[]> = {};
  const missing: string[] = [];
  for (const id of new Set(productIds)) {
    const hit = readStored<EbaySummary[]>(`holo:ebaysum:${id}`);
    if (hit) out[id] = hit;
    else missing.push(id);
  }
  if (missing.length) {
    const r = await fetch(`/api/tcg/ebay?ids=${encodeURIComponent(missing.sort().join(","))}`);
    const body = await r.json().catch(() => null);
    if (!r.ok) throw new EbayLoadError(body?.error?.message ?? "Couldn't load eBay data.", body?.error?.code === "tier");
    for (const id of missing) {
      out[id] = (body?.ebay?.[id] ?? []) as EbaySummary[];
      store(`holo:ebaysum:${id}`, out[id]);
    }
  }
  return out;
}

/** TCGplayer prices per condition for a card, from this device or the server. */
export async function loadConditions(productId: string, printing: string | null): Promise<ConditionPrice[]> {
  const key = `holo:conditions:${productId}:${printing ?? ""}`;
  const hit = readStored<ConditionPrice[]>(key);
  if (hit) return hit;
  const r = await fetch(`/api/tcg/products/${encodeURIComponent(productId)}/conditions${printing ? `?printing=${encodeURIComponent(printing)}` : ""}`);
  const body = await r.json().catch(() => null);
  if (!r.ok) throw new EbayLoadError(body?.error?.message ?? "Couldn't load condition prices.", body?.error?.code === "tier");
  const value = (body?.conditions ?? []) as ConditionPrice[];
  store(key, value);
  return value;
}

/** A summary's row for a printing, else the first one. */
export function summaryFor(rows: EbaySummary[] | undefined, printing: string | null): EbaySummary | null {
  if (!rows?.length) return null;
  return rows.find((r) => r.printing === printing) ?? rows[0];
}
