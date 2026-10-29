import type { EbaySales } from "./ebay-types";

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
