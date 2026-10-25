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
  type Set as TcgSet,
} from "tcgapi";
import { inferKind } from "../catalog";
import { compareCollectorNumbers } from "../collector-number";
import { parseQuery, rankByQuery } from "../search-query";
import type { NormalizedPrice, PriceStatus, Product, ProductKind } from "../types";
import { cached } from "./cache";
import {
  PricingUnavailableError,
  type HistoryResult,
  type MoverHit,
  type PricingProvider,
  type GameFilter,
  type ProductTypeFilter,
  type SearchQuery,
  type SearchHit,
  type SearchResult,
  type SetChecklist,
} from "./types";

/** Game slug for English Pokémon on TCG API (used for top movers). */
export const POKEMON_GAME = process.env.TCGAPI_GAME ?? "pokemon";

const MIN = 60_000;
const HOUR = 60 * MIN;
/** A source price older than this is shown as stale. */
const STALE_AFTER_MS = 72 * HOUR;

/** Longest pause after a 429, so a plan upgrade or the daily reset takes effect quickly. */
const MAX_COOLDOWN_MS = 10 * MIN;

/**
 * The latest budget TCG API reported (shown in Settings). Requests are never
 * blocked pre-emptively; we only back off after a real 429.
 */
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

function limitMessage(): string {
  const reset = rateLimit?.daily_reset ? new Date(rateLimit.daily_reset) : null;
  const when = reset && !Number.isNaN(reset.getTime()) ? ` It resets ${reset.toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short" })}.` : "";
  return `TCG API says today's request limit has been reached.${when}`;
}

/** Wrap every SDK call: honour a 429 cool-down, record the live budget, and translate SDK errors. */
async function call<T>(fn: (c: TCGApi) => Promise<{ data: T; rateLimit?: RateLimit; meta?: unknown }>) {
  if (Date.now() < cooldownUntil) {
    throw new PricingUnavailableError(limitMessage(), "rate_limited", Math.ceil((cooldownUntil - Date.now()) / 1000));
  }
  try {
    const res = await fn(api());
    if (res.rateLimit) rateLimit = res.rateLimit;
    return res;
  } catch (err) {
    if (err instanceof RateLimitError) {
      const retry = Math.min(err.retryAfter ?? 600, MAX_COOLDOWN_MS / 1000);
      cooldownUntil = Date.now() + retry * 1000;
      throw new PricingUnavailableError(limitMessage(), "rate_limited", retry);
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

interface GameRef {
  slug: string;
  name: string;
  franchise: Exclude<GameFilter, "all">;
}

function franchiseOf(text: string): GameRef["franchise"] | null {
  if (/pok[eé]mon/i.test(text)) return "pokemon";
  if (/lorcana/i.test(text)) return "lorcana";
  return null;
}

const FALLBACK_GAMES: GameRef[] = [
  { slug: "pokemon", name: "Pokemon", franchise: "pokemon" },
  { slug: "lorcana", name: "Lorcana", franchise: "lorcana" },
];

/**
 * Every catalog Holo searches: all Pokémon catalogs (English, Japanese, …)
 * and Disney Lorcana. Japanese products such as "MEGA Dream ex" live under a
 * separate game, so searching only the English game misses them. Discovered
 * once a day from GET /games; override with TCGAPI_GAMES="slug-a,slug-b".
 */
async function catalogGames(): Promise<GameRef[]> {
  const override = process.env.TCGAPI_GAMES;
  if (override) {
    return override
      .split(",")
      .map((slug) => slug.trim())
      .filter(Boolean)
      .map((slug) => ({ slug, name: slug, franchise: franchiseOf(slug) ?? "pokemon" }));
  }
  try {
    return await cached("games:catalogs", 24 * HOUR, async () => {
      const res = await call((c) => c.games.list({ per_page: 200 }));
      const games = res.data.flatMap((g) => {
        const franchise = franchiseOf(`${g.name} ${g.slug}`);
        return franchise ? [{ slug: g.slug, name: g.name, franchise }] : [];
      });
      // English Pokémon first so it wins ties in ranking.
      games.sort((a, b) => (a.slug === "pokemon" ? -1 : b.slug === "pokemon" ? 1 : a.name.localeCompare(b.name)));
      return games.length ? games : FALLBACK_GAMES;
    });
  } catch {
    return FALLBACK_GAMES;
  }
}

async function rawSearch(q: string, type: ProductTypeFilter, page: number, perPage: number | undefined, game: GameRef): Promise<SearchResult> {
  return cached(`search:${game.slug}:${type}:${page}:${q}`, 30 * MIN, async () => {
    const res = await call((c) =>
      c.search.cards({ q, game: game.slug, type: typeParam(type), page, per_page: Math.min(perPage ?? 30, 50) }),
    );
    const hint: ProductKind | undefined = type === "sealed" ? "sealed" : type === "cards" ? "single" : undefined;
    return {
      hits: res.data.map((card) => ({
        product: toProduct(card, hint),
        printing: card.printing ?? null,
        market: card.market_price ?? null,
        priceUpdatedAt: card.price_updated_at ?? null,
        gameName: card.game_name ?? game.name,
      })),
      total: (res.meta as { total?: number } | undefined)?.total ?? res.data.length,
      hasMore: Boolean((res.meta as { has_more?: boolean } | undefined)?.has_more),
    };
  });
}

/** Search the selected catalogs in parallel and merge. */
async function searchAllGames(q: string, type: ProductTypeFilter, game: GameFilter, page: number, perPage?: number): Promise<SearchResult> {
  const games = (await catalogGames()).filter((g) => game === "all" || g.franchise === game);
  if (!games.length) return { hits: [], total: 0, hasMore: false };
  const results = await Promise.allSettled(games.map((g) => rawSearch(q, type, page, perPage, g)));
  const ok = results.filter((r): r is PromiseFulfilledResult<SearchResult> => r.status === "fulfilled").map((r) => r.value);
  if (!ok.length) {
    const failure = results.find((r): r is PromiseRejectedResult => r.status === "rejected");
    throw failure?.reason ?? new PricingUnavailableError("Search failed.", "upstream");
  }
  return {
    hits: ok.flatMap((r) => r.hits),
    total: ok.reduce((s, r) => s + r.total, 0),
    hasMore: ok.some((r) => r.hasMore),
  };
}

export const tcgApiProvider: PricingProvider = {
  source: "tcgapi",

  /**
   * Forgiving search: try the query as typed, then progressively looser
   * variants (see search-query.ts) only when a stricter one finds nothing.
   * If the type filter returns nothing we retry unfiltered and filter
   * locally, so a catalog quirk in product typing can't hide results.
   * At most MAX_ATTEMPTS attempts (one call per Pokémon catalog each),
   * cached for 30 minutes.
   */
  async search(query: SearchQuery): Promise<SearchResult> {
    const parsed = parseQuery(query.q);
    // Each attempt queries every Pokémon catalog (English + Japanese).
    const MAX_ATTEMPTS = 3;
    let attempts = 0;
    const wanted = (hit: SearchHit) =>
      query.type === "all" || (query.type === "sealed" ? hit.product.kind === "sealed" : hit.product.kind === "single");

    for (const variant of parsed.variants) {
      const types: ProductTypeFilter[] = query.type === "all" ? ["all"] : [query.type, "all"];
      for (const type of types) {
        if (attempts >= MAX_ATTEMPTS) break;
        attempts++;
        const res = await searchAllGames(variant, type, query.game ?? "pokemon", query.page ?? 1, query.perPage);
        // Unfiltered retries are classified locally (rawSearch infers kind when untyped).
        const hits = type === query.type ? res.hits : res.hits.filter(wanted);
        if (hits.length) {
          return {
            hits: rankByQuery(hits, parsed),
            total: type === query.type ? res.total : hits.length,
            hasMore: type === query.type && res.hasMore,
            relaxedQuery: variant === parsed.variants[0] ? null : variant,
          };
        }
      }
    }
    return { hits: [], total: 0, hasMore: false, relaxedQuery: null };
  },

  async getProduct(externalId: string): Promise<Product> {
    return cached(`product:${externalId}`, 24 * HOUR, async () => {
      const res = await call((c) => c.cards.get(Number(externalId)));
      return toProduct(res.data);
    });
  },

  async getPrices(externalId: string): Promise<NormalizedPrice[]> {
    return cached(`prices:${externalId}`, HOUR, async () => {
      const res = await call((c) => c.cards.prices(Number(externalId)));
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
    const res = await call((c) => c.bulk.prices(externalIds.map(Number)));
    return res.data.map((row) => normalizePrice(`tcgapi:${row.card_id}`, row as Price));
  } catch (err) {
    if (err instanceof PricingUnavailableError && err.code === "tier") return null;
    throw err;
  }
}

/** Every set across Holo's catalogs, keyed by slug. Refreshed daily. */
async function setIndex(): Promise<Map<string, TcgSet>> {
  return cached("sets:index", 24 * HOUR, async () => {
    const index = new Map<string, TcgSet>();
    for (const game of await catalogGames()) {
      for (let page = 1; page <= 5; page++) {
        const res = await call((c) => c.games.sets(game.slug, { page, per_page: 200 }));
        for (const set of res.data) index.set(set.slug, set);
        if (!(res.meta as { has_more?: boolean } | undefined)?.has_more && res.data.length < 200) break;
      }
    }
    return index;
  });
}

/** Singles in a set, in collector-number order, with primary-printing prices. */
export async function setChecklist(slug: string): Promise<SetChecklist> {
  return cached(`checklist:${slug}`, 24 * HOUR, async () => {
    const set = (await setIndex()).get(slug);
    if (!set) throw new PricingUnavailableError("That set wasn't found in the catalog.", "not_found");
    const cards: SetChecklist["cards"] = [];
    for (let page = 1; page <= 6; page++) {
      const res = await call((c) => c.sets.cards(set.id, { type: "Cards", sort: "number", page, per_page: 200 }));
      for (const card of res.data) {
        if (cards.some((c) => c.productId === `tcgapi:${card.id}`)) continue;
        cards.push({
          productId: `tcgapi:${card.id}`,
          number: card.number ?? null,
          name: card.name,
          rarity: card.rarity ?? null,
          imageUrl: card.image_url ?? null,
          market: card.market_price ?? null,
        });
      }
      if (!(res.meta as { has_more?: boolean } | undefined)?.has_more) break;
    }
    cards.sort((a, b) => compareCollectorNumbers(a.number, b.number));
    return { setId: slug, name: set.name, releaseDate: set.release_date, iconUrl: set.set_icon_url ?? set.image_url, cards };
  });
}

/* ------------------------- Explore catalog sync -------------------------- */

/** Requests left today, as last reported by TCG API (null until the first call). */
export function dailyRemaining(): number | null {
  return rateLimit?.daily_remaining ?? null;
}

/** Catalogs (games) Holo covers, for the catalog sync. */
export async function catalogGameList(): Promise<{ slug: string; name: string }[]> {
  return (await catalogGames()).map(({ slug, name }) => ({ slug, name }));
}

/** One page of a game's sets. Uncached: the catalog sync stores the result. */
export async function gameSetsPage(gameSlug: string, page: number): Promise<{ sets: TcgSet[]; hasMore: boolean }> {
  const res = await call((c) => c.games.sets(gameSlug, { page, per_page: 200 }));
  const more = (res.meta as { has_more?: boolean } | undefined)?.has_more;
  return { sets: res.data, hasMore: more ?? res.data.length === 200 };
}

/** One page of every product (singles and sealed) in a set, with primary-printing prices. */
export async function setProductsPage(
  set: { id: number; slug: string; name: string },
  page: number,
): Promise<{ products: Product[]; prices: NormalizedPrice[]; hasMore: boolean }> {
  const res = await call((c) => c.sets.cards(set.id, { page, per_page: 200, sort: "number" }));
  const products: Product[] = [];
  const prices: NormalizedPrice[] = [];
  for (const card of res.data) {
    const product = { ...toProduct(card), setName: set.name, setId: set.slug };
    products.push(product);
    prices.push(
      normalizePrice(product.id, {
        printing: card.printing,
        market_price: card.market_price,
        low_price: card.low_price,
        price_change_24h: null,
        price_change_7d: null,
        price_change_30d: null,
        last_updated_at: (card.price_updated_at ?? null) as string,
      }),
    );
  }
  const more = (res.meta as { has_more?: boolean } | undefined)?.has_more;
  return { products, prices, hasMore: more ?? res.data.length === 200 };
}
