import type { SupabaseClient } from "@supabase/supabase-js";
import { THEMES, THEME_LOOKS, orList, pickFor, type Theme, type ThemeRule } from "../explore/themes";
import type { ExploreMarket } from "../explore/movers";
import type { ExploreProduct } from "../explore/types";
import type { Database, ProductRow } from "../supabase/database.types";
import { aiEnabled, aiJson } from "./ai";
import { dbCached } from "./api-cache";
import { exploreMarket, withPrices } from "./explore";
import { selectAll } from "./paging";

const HOUR = 60 * 60 * 1000;
/** Rows read per theme: plenty for any one Pokémon or set, and a single quick read. */
const READ = 1000;

/** What one fill shares between themes (read once, only if a theme needs it). */
interface Shared {
  market?: Promise<ExploreMarket | null>;
  artPool?: Promise<ExploreProduct[]>;
}

const meta = (rule: ThemeRule, hits: ExploreProduct[], curated = false): Theme => ({
  id: rule.id,
  title: rule.title,
  blurb: rule.blurb,
  look: rule.look,
  pokemon: rule.pokemon,
  era: rule.era,
  featured: rule.featured,
  fresh: rule.fresh,
  curated: curated || undefined,
  hits,
});

/** Cards whose name, set, number or rarity fit, read straight from the catalog. */
async function byRule(admin: SupabaseClient<Database>, rule: ThemeRule): Promise<ExploreProduct[]> {
  const names = orList("name", rule.names);
  const sets = orList("set_name", rule.sets);
  const numbers = orList("number", rule.numbers, true);
  const rarities = orList("rarity", rule.rarities);
  const page = (from: number, to: number) => {
    let q = admin.from("products").select("*").eq("kind", "single");
    if (names) q = q.or(names);
    if (sets) q = q.or(sets);
    if (numbers) q = q.or(numbers);
    // Rarity alone is broad: it's the only filter when nothing else narrows it.
    if (rarities && !names && !sets && !numbers) q = q.or(rarities);
    return q.order("id").range(from, to);
  };
  const rows = names || sets || numbers ? await selectAll<ProductRow>(page, READ) : await selectAll<ProductRow>(page, 5000);
  return withPrices(admin, rows);
}

/** Cards read from the priciest down within the rule's price band (grails, price finds). */
async function byPrice(admin: SupabaseClient<Database>, rule: ThemeRule): Promise<ExploreProduct[]> {
  let q = admin.from("product_prices").select("product_id").not("market_price", "is", null);
  if (rule.minPrice !== undefined) q = q.gte("market_price", rule.minPrice);
  if (rule.maxPrice !== undefined) q = q.lte("market_price", rule.maxPrice);
  const { data, error } = await q.order("market_price", { ascending: false }).limit(3000);
  if (error) return [];
  const ids = [...new Set((data ?? []).map((r) => r.product_id))];
  const rows: ProductRow[] = [];
  for (let i = 0; i < ids.length; i += 150) {
    const { data: part } = await admin.from("products").select("*").eq("kind", "single").in("id", ids.slice(i, i + 150));
    rows.push(...((part ?? []) as ProductRow[]));
  }
  return withPrices(admin, rows);
}

/** Cards from Pokémon sets out in the last 90 days. */
async function freshCards(admin: SupabaseClient<Database>): Promise<ExploreProduct[]> {
  const today = new Date().toISOString().slice(0, 10);
  const since = new Date(Date.now() - 90 * 24 * HOUR).toISOString().slice(0, 10);
  const { data: sets } = await admin.from("catalog_sets").select("slug, game_name").gte("release_date", since).lte("release_date", today);
  const slugs = (sets ?? []).filter((s) => /pok/i.test(s.game_name) && !/japan/i.test(s.game_name)).map((s) => s.slug);
  if (!slugs.length) return [];
  const rows = await selectAll<ProductRow>((from, to) => admin.from("products").select("*").eq("kind", "single").in("set_id", slugs).order("id").range(from, to), 4000);
  return withPrices(admin, rows);
}

/** Cards kept or watched by at least two Dexora collectors, most people first. */
async function popularCards(admin: SupabaseClient<Database>): Promise<ExploreProduct[]> {
  const people = new Map<string, Set<string>>();
  const add = (rows: { user_id: string; product_id: string }[] | null) => {
    for (const r of rows ?? []) people.set(r.product_id, (people.get(r.product_id) ?? new Set()).add(r.user_id));
  };
  const [held, watched] = await Promise.all([
    selectAll<{ user_id: string; product_id: string }>((from, to) => admin.from("holdings").select("user_id, product_id").order("product_id").range(from, to), 20_000),
    selectAll<{ user_id: string; product_id: string }>((from, to) => admin.from("watchlist_items").select("user_id, product_id").order("product_id").range(from, to), 20_000),
  ]);
  add(held);
  add(watched);
  // Two people or more, so no one's own collection shows to others.
  const ids = [...people].filter(([, who]) => who.size >= 2).sort((a, b) => b[1].size - a[1].size).slice(0, 60).map(([id]) => id);
  if (!ids.length) return [];
  const { data } = await admin.from("products").select("*").in("id", ids);
  const priced = await withPrices(admin, (data ?? []) as ProductRow[]);
  return priced.sort((a, b) => ids.indexOf(a.product.id) - ids.indexOf(b.product.id));
}

/** The day's market lists, as a theme's cards. */
function marketCards(market: ExploreMarket | null, which: ThemeRule["market"]): ExploreProduct[] {
  if (!market) return [];
  switch (which) {
    case "today":
      return market.today;
    case "drops":
      return market.drops;
    case "rediscovered":
      return [...market.eras.vintage, ...market.eras.midEra];
    default:
      return market.trending;
  }
}

/** The illustration cards the AI chooses from for art themes (English, priced). */
async function artPool(admin: SupabaseClient<Database>): Promise<ExploreProduct[]> {
  const rows = await selectAll<ProductRow>(
    (from, to) => admin.from("products").select("*").eq("kind", "single").or("rarity.ilike.*Illustration*,number.ilike.TG*,number.ilike.GG*").order("id").range(from, to),
    6000,
  );
  const priced = await withPrices(admin, rows);
  return priced
    .filter((p) => p.market !== null && p.market >= 1 && /pok/i.test(p.gameName ?? "pokemon") && !/japan/i.test(p.gameName ?? ""))
    .sort((a, b) => (b.market ?? 0) - (a.market ?? 0))
    .slice(0, 2500);
}

/** This week's AI picks for an art theme: card ids, chosen from the pool by name and set. */
async function aiPicks(rule: ThemeRule, pool: ExploreProduct[], week: string): Promise<string[]> {
  return dbCached<string[]>(
    `theme-ai:${rule.id}:${week}`,
    async () => {
      const list = pool.filter((p) => rule.maxPrice === undefined || (p.market ?? 0) <= rule.maxPrice);
      if (list.length < 10) return [];
      const lines = list.map((p, i) => `${i}. ${p.product.name} | ${p.product.setName ?? ""} | $${Math.round(p.market ?? 0)}`).join("\n");
      const answer = await aiJson<{ picks: number[] }>(
        "art_picks",
        PICK_SYSTEM,
        `Collection: "${rule.title}" (${rule.blurb})\nLook for: ${rule.brief ?? rule.blurb}\n\nCards:\n${lines}`,
        PICK_SCHEMA,
      ).catch((e) => {
        console.error("theme picks", rule.id, e);
        return null;
      });
      return [...new Set((answer?.picks ?? []).filter((i) => Number.isInteger(i) && list[i]).map((i) => list[i].product.id))].slice(0, 20);
    },
    (v) => (v.length ? 8 * 24 * HOUR : HOUR),
  );
}

const PICK_SYSTEM = `You curate art collections of Pokémon cards for Dexora, a collection app. You get a collection's idea and a numbered list of cards (name | set | price). From what you know of each card's artwork, choose the 12 to 20 cards that best fit the idea. Only choose cards you're confident fit; fewer is better than wrong. Answer with their numbers, best first.`;

const PICK_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["picks"],
  properties: { picks: { type: "array", items: { type: "integer" } } },
};

/** One theme's cards: from our own data (no TCG API), saved for the day. */
async function themeCards(admin: SupabaseClient<Database>, rule: ThemeRule, day: string, shared: Shared): Promise<Theme | null> {
  return dbCached<Theme | null>(
    `theme:${rule.id}:${day}`,
    async () => {
      switch (rule.source) {
        case "market": {
          shared.market ??= exploreMarket(admin).catch(() => null);
          const hits = pickFor({ ...rule, minPrice: undefined, maxPrice: undefined }, marketCards(await shared.market, rule.market), 20, true);
          return hits.length >= 3 ? meta(rule, hits) : null;
        }
        case "popular": {
          const hits = pickFor(rule, await popularCards(admin), 24, true);
          return hits.length >= 3 ? meta(rule, hits) : null;
        }
        case "ai": {
          if (!aiEnabled()) return null;
          shared.artPool ??= artPool(admin).catch(() => []);
          const pool = await shared.artPool;
          const ids = await aiPicks(rule, pool, weekOf());
          const byId = new Map(pool.map((p) => [p.product.id, p]));
          const hits = ids.flatMap((id) => (byId.get(id) ? [byId.get(id)!] : []));
          return hits.length >= 3 ? meta(rule, pickFor({ ...rule, maxPrice: undefined }, hits, 20, true), true) : null;
        }
        default: {
          const all = rule.source === "price" ? await byPrice(admin, rule) : rule.source === "fresh" ? await freshCards(admin) : await byRule(admin, rule);
          const hits = pickFor(rule, all);
          return hits.length >= 3 ? meta(rule, hits) : null;
        }
      }
    },
    // A filled theme keeps for the day; an empty one is tried again in a few hours.
    (v) => (v ? 26 * HOUR : 4 * HOUR),
  );
}

/**
 * Every theme with its cards (ours plus this week's ideas from AI). Themes not saved yet are
 * filled a few at a time within a time budget; the rest fill on the next ask, so this never
 * keeps the app waiting long.
 */
export async function themes(admin: SupabaseClient<Database>): Promise<Theme[]> {
  const day = new Date().toISOString().slice(0, 10);
  const rules = [...THEMES, ...(await themeIdeas().catch(() => []))];
  const started = Date.now();
  const shared: Shared = {};
  const out: Theme[] = [];
  for (let i = 0; i < rules.length; i += 6) {
    if (Date.now() - started > 40_000) break;
    const batch = await Promise.all(rules.slice(i, i + 6).map((r) => themeCards(admin, r, day, shared).catch(() => null)));
    for (const t of batch) if (t) out.push(t);
  }
  return out;
}

// MARK: New themes from AI (OpenAI, see ai.ts), once a week

const SYSTEM = `You curate themed collections of Pokémon cards for Dexora, a collection app. Each theme is a rule over a card catalog (English and Japanese Pokémon TCG cards with their set names, card names, rarities, numbers and market prices).
Propose new themes that collectors would find fun to browse: a Pokémon or group of Pokémon, an era, a set or subset, an art style shown by rarity, a price band. Make them different from the existing titles you're given. Prefer well-known Pokémon, sets and subsets that surely exist in the catalog.
Rules: "names", "sets", "rarities" are substrings matched case-insensitively (any one of the list); "numbers" match the start of the card number (like "TG" or "SV"). Keep lists short and precise. Give a "minPrice" of at least 5. "look" is one of: billboard (one big hero card), fan (a hand of cards), timeline (one Pokémon across the years, needs names), mosaic (a wall of art), ladder (one Pokémon at every price, needs names), spotlight (one standout card). Titles in sentence case, at most 32 characters; blurbs one line, at most 70 characters, plain and warm, no hype, no emojis.`;

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["themes"],
  properties: {
    themes: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["title", "blurb", "look", "names", "sets", "rarities", "numbers", "minPrice", "pokemon"],
        properties: {
          title: { type: "string" },
          blurb: { type: "string" },
          look: { type: "string", enum: THEME_LOOKS },
          names: { type: "array", items: { type: "string" } },
          sets: { type: "array", items: { type: "string" } },
          rarities: { type: "array", items: { type: "string" } },
          numbers: { type: "array", items: { type: "string" } },
          minPrice: { type: "number" },
          pokemon: { type: "array", items: { type: "string" } },
        },
      },
    },
  },
};

/** Monday of this week, for the weekly key. */
function weekOf(d = new Date()): string {
  const m = new Date(d);
  m.setUTCDate(m.getUTCDate() - ((m.getUTCDay() + 6) % 7));
  return m.toISOString().slice(0, 10);
}

/** This week's new themes from AI (none without OPENAI_API_KEY). One request a week. */
export async function themeIdeas(): Promise<ThemeRule[]> {
  if (!aiEnabled()) return [];
  const week = weekOf();
  return dbCached<ThemeRule[]>(
    `theme-ideas:${week}`,
    async () => {
      try {
        const parsed = await aiJson<{ themes: (Omit<ThemeRule, "id"> & { look: string })[] }>(
          "new_themes",
          SYSTEM,
          `Existing themes:\n${THEMES.map((t) => `- ${t.title}`).join("\n")}\n\nPropose 5 new themes for the week of ${week}.`,
          SCHEMA,
        );
        if (!parsed) return [];
        return (parsed.themes ?? [])
          .filter((t) => THEME_LOOKS.includes(t.look as never) && t.title.trim() && (t.names?.length || t.sets?.length || t.numbers?.length))
          .slice(0, 5)
          .map((t, i) => ({
            ...t,
            id: `new-${week}-${i}`,
            title: t.title.trim().slice(0, 40),
            blurb: t.blurb.trim().slice(0, 90),
            look: t.look as ThemeRule["look"],
            minPrice: Math.max(5, t.minPrice || 5),
            fresh: true,
          }));
      } catch (e) {
        console.error("theme ideas", e);
        return [];
      }
    },
    (v) => (v.length ? 8 * 24 * HOUR : HOUR),
  );
}
