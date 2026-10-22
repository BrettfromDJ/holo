import "server-only";
import {
  AuthError,
  NotFoundError,
  RateLimitError,
  TCGApi,
  TierError,
  type Card,
  type CardWithPrice,
  type Price,
  type PriceMover,
  type RateLimit,
} from "tcgapi";
import { inferKind } from "../catalog";
import type { NormalizedPrice, PriceStatus, Product, ProductKind } from "../types";
import { cached } from "./cache";
import {
  PricingUnavailableError,
  type HistoryResult,
  type MoverHit,
  type PricingProvider,
  type ProductTypeFilter,
  type SearchQuery,
  type SearchResult,
} from "./types";

/** Game slug for English Pokémon on TCG API. */
export const POKEMON_GAME = process.env.TCGAPI_GAME ?? "pokemon";

const MIN = 60_000;
const HOUR = 60 * MIN;
/** A source price older than this is shown as stale. */
const STALE_AFTER_MS = 72 * HOUR;
/** Keep this many daily requests in reserve for the scheduled price sync. */
const DAILY_RESERVE = Number(process.env.TCGAPI_DAILY_RESERVE ?? 10);

let rateLimit: RateLimit | null = null;
let cooldownUntil = 0;

export function rateLimitStatus() {
  return { rateLimit, cooldownUntil: cooldownUntil > Date.now() ? new Date(cooldownUntil).toISOString() : null };
}

export function isTcgApiConfigured(): boolean {
  return Boolean(process.env.TCGAPI_KEY);
}

let client: TCGApi | null = null;
function api(): TCGApi {
  if (!process.env.TCGAPI_KEY) throw new PricingUnavailableError("TCG API key is not configured.", "not_configured");
  client ??= new TCGApi({ apiKey: process.env.TCGAPI_KEY, timeoutMs: 15_000, userAgent: "holo-collection-tracker" });
  return client;
}

/**
 * Wrap every SDK call: honour cool-downs, keep a reserve of daily requests
 * for background jobs, record the live budget, and translate SDK errors.
 */
async function call<T>(fn: (c: TCGApi) => Promise<{ data: T; rateLimit?: RateLimit; meta?: unknown }>, opts: { essential?: boolean } = {}) {
  if (Date.now() < cooldownUntil) {
    throw new PricingUnavailableError("TCG API daily limit reached. Prices will refresh later.", "rate_limited", Math.ceil((cooldownUntil - Date.now()) / 1000));
  }
  if (!opts.essential && rateLimit && rateLimit.daily_remaining <= DAILY_RESERVE) {
    throw new PricingUnavailableError("TCG API request budget is reserved for the daily price sync.", "rate_limited");
  }
  try {
    const res = await fn(api());
    if (res.rateLimit) rateLimit = res.rateLimit;
    return res;
  } catch (err) {
    if (err instanceof RateLimitError) {
      const retry = err.retryAfter ?? 3600;
      cooldownUntil = Date.now() + retry * 1000;
      throw new PricingUnavailableError("TCG API rate limit reached.", "rate_limited", retry);
    }
    if (err instanceof TierError) throw new PricingUnavailableError("This feature isn't included in the current TCG API plan.", "tier");
    if (err instanceof AuthError) throw new PricingUnavailableError("The TCG API key was rejected.", "auth");
    if (err instanceof NotFoundError) throw new PricingUnavailableError("Product not found.", "not_found");
    if (err instanceof PricingUnavailableError) throw err;
    throw new PricingUnavailableError(err instanceof Error ? err.message : "TCG API request failed.", "upstream");
  }
}

function typeParam(type: ProductTypeFilter | undefined): "Cards" | "Sealed Products" | undefined {
  if (type === "cards") return "Cards";
  if (type === "sealed") return "Sealed Products";
  return undefined;
}

function toProduct(card: Card | CardWithPrice | PriceMover, kindHint?: ProductKind): Product {
  const c = card as Partial<Card> & { id?: number; card_id?: number };
  const id = String(c.id ?? c.card_id);
  const number = c.number ?? null;
  return {
    id: `tcgapi:${id}`,
    source: "tcgapi",
    externalId: id,
    name: card.name,
    setName: c.set_name ?? null,
    setId: c.set_slug ?? null,
    number,
    rarity: c.rarity ?? null,
    productType: card.product_type ?? null,
    kind: inferKind({ productType: card.product_type ?? null, number, name: card.name }, kindHint),
    imageUrl: card.image_url ?? null,
    tcgplayerId: card.tcgplayer_id ?? null,
    tcgplayerUrl: c.tcgplayer_url ?? null,
  };
}

function statusFor(market: number | null, updatedAt: string | null): PriceStatus {
  if (market === null) return "unavailable";
  if (!updatedAt) return "stale";
  return Date.now() - Date.parse(updatedAt) > STALE_AFTER_MS ? "stale" : "live";
}

export function normalizePrice(productId: string, p: Pick<Price, "printing" | "market_price" | "low_price" | "price_change_24h" | "price_change_7d" | "price_change_30d" | "last_updated_at">): NormalizedPrice {
  const updatedAt = p.last_updated_at ?? null;
  return {
    productId,
    printing: p.printing ?? null,
    market: p.market_price ?? null,
    low: p.low_price ?? null,
    // TCG API reports price changes as percentages.
    change24hPct: p.price_change_24h ?? null,
    change7dPct: p.price_change_7d ?? null,
    change30dPct: p.price_change_30d ?? null,
    updatedAt,
    fetchedAt: new Date().toISOString(),
    source: "tcgapi",
    status: statusFor(p.market_price ?? null, updatedAt),
  };
}

export const tcgApiProvider: PricingProvider = {
  source: "tcgapi",

  async search(query: SearchQuery): Promise<SearchResult> {
    const q = query.q.trim();
    const key = `search:${query.type}:${query.page ?? 1}:${q.toLowerCase()}`;
    return cached(key, 30 * MIN, async () => {
      const res = await call((c) =>
        c.search.cards({
          q,
          game: POKEMON_GAME,
          type: typeParam(query.type),
          page: query.page ?? 1,
          per_page: Math.min(query.perPage ?? 24, 50),
        }),
      );
      const hint: ProductKind | undefined = query.type === "sealed" ? "sealed" : query.type === "cards" ? "single" : undefined;
      return {
        hits: res.data.map((card) => ({
          product: toProduct(card, hint),
          printing: card.printing ?? null,
          market: card.market_price ?? null,
          priceUpdatedAt: card.price_updated_at ?? null,
        })),
        total: (res.meta as { total?: number } | undefined)?.total ?? res.data.length,
        hasMore: Boolean((res.meta as { has_more?: boolean } | undefined)?.has_more),
      };
    });
  },

  async getProduct(externalId: string): Promise<Product> {
    return cached(`product:${externalId}`, 24 * HOUR, async () => {
      const res = await call((c) => c.cards.get(Number(externalId)), { essential: true });
      return toProduct(res.data);
    });
  },

  async getPrices(externalId: string): Promise<NormalizedPrice[]> {
    return cached(`prices:${externalId}`, HOUR, async () => {
      const res = await call((c) => c.cards.prices(Number(externalId)), { essential: true });
      return res.data.map((p) => normalizePrice(`tcgapi:${externalId}`, p));
    });
  },

  async getHistory(externalId, printing, range): Promise<HistoryResult> {
    return cached(`history:${externalId}:${printing ?? ""}:${range}`, 6 * HOUR, async () => {
      try {
        const res = await call((c) => c.cards.history(Number(externalId), { range, printing: printing ?? undefined }));
        const byDate = new Map<string, number>();
        for (const point of res.data) {
          // History may contain several printings; keep the requested one.
          if (printing && point.printing && point.printing !== printing) continue;
          if (point.market_price === null || point.market_price === undefined) continue; // never treat missing as 0
          byDate.set(point.date.slice(0, 10), point.market_price);
        }
        const points = [...byDate.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([date, price]) => ({ date, price }));
        return { points, available: true };
      } catch (err) {
        if (err instanceof PricingUnavailableError && err.code === "tier") {
          return { points: [], available: false, reason: "Price history isn't included in the current TCG API plan." };
        }
        throw err;
      }
    });
  },

  async topMovers({ direction, period, type, limit = 10 }): Promise<MoverHit[]> {
    return cached(`movers:${direction}:${period}:${type ?? "all"}:${limit}`, 2 * HOUR, async () => {
      const res = await call((c) => c.prices.topMovers({ game: POKEMON_GAME, direction, period, type: typeParam(type), limit }));
      return res.data.map((m) => ({
        product: toProduct(m, type === "sealed" ? "sealed" : undefined),
        printing: m.printing ?? null,
        market: m.market_price,
        changePct: m.price_change,
      }));
    });
  },
};

/** Bulk current prices (Pro+). Returns null when the plan doesn't include it. */
export async function bulkPrices(externalIds: string[]): Promise<NormalizedPrice[] | null> {
  try {
    const res = await call((c) => c.bulk.prices(externalIds.map(Number)), { essential: true });
    return res.data.map((row) => normalizePrice(`tcgapi:${row.card_id}`, row as Price));
  } catch (err) {
    if (err instanceof PricingUnavailableError && err.code === "tier") return null;
    throw err;
  }
}
