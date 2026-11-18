import Anthropic from "@anthropic-ai/sdk";
import type { SupabaseClient } from "@supabase/supabase-js";
import { THEMES, THEME_LOOKS, orList, pickFor, type Theme, type ThemeRule } from "../explore/themes";
import type { Database, ProductRow } from "../supabase/database.types";
import { dbCached } from "./api-cache";
import { withPrices } from "./explore";

const HOUR = 60 * 60 * 1000;
/** Rows read per theme: plenty for any one Pokémon or set, and a single quick read. */
const READ = 1000;

/** One theme's cards: read from our catalog (no TCG API), saved for the day. */
async function themeCards(admin: SupabaseClient<Database>, rule: ThemeRule, day: string): Promise<Theme | null> {
  const theme = await dbCached<Theme | null>(
    `theme:${rule.id}:${day}`,
    async () => {
      let q = admin.from("products").select("*").eq("kind", "single");
      const names = orList("name", rule.names);
      const sets = orList("set_name", rule.sets);
      const numbers = orList("number", rule.numbers, true);
      const rarities = orList("rarity", rule.rarities);
      if (names) q = q.or(names);
      if (sets) q = q.or(sets);
      if (numbers) q = q.or(numbers);
      // Rarity is only narrowed in the database when nothing else is (it's broad on its own).
      if (rarities && !names && !sets && !numbers) q = q.or(rarities);
      const { data, error } = await q.limit(READ);
      if (error) return null;
      const priced = await withPrices(admin, (data ?? []) as ProductRow[]);
      const hits = pickFor(rule, priced);
      if (hits.length < 3) return null;
      return { id: rule.id, title: rule.title, blurb: rule.blurb, look: rule.look, pokemon: rule.pokemon, era: rule.era, fresh: rule.fresh, hits };
    },
    // A filled theme keeps for the day; an empty one is tried again in a few hours.
    (v) => (v ? 26 * HOUR : 4 * HOUR),
  );
  return theme;
}

/**
 * Every theme with its cards (ours plus this week's ideas from Claude). Themes not saved yet are
 * filled a few at a time within a time budget; the rest fill on the next ask, so this never
 * keeps the app waiting long.
 */
export async function themes(admin: SupabaseClient<Database>): Promise<Theme[]> {
  const day = new Date().toISOString().slice(0, 10);
  const rules = [...THEMES, ...(await themeIdeas().catch(() => []))];
  const started = Date.now();
  const out: Theme[] = [];
  for (let i = 0; i < rules.length; i += 6) {
    if (Date.now() - started > 20_000) break;
    const batch = await Promise.all(rules.slice(i, i + 6).map((r) => themeCards(admin, r, day).catch(() => null)));
    for (const t of batch) if (t) out.push(t);
  }
  return out;
}

// MARK: New themes from Claude, once a week

const MODEL = "claude-opus-5-5";

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

/** This week's new themes from Claude (none without ANTHROPIC_API_KEY). One request a week. */
export async function themeIdeas(): Promise<ThemeRule[]> {
  if (!process.env.ANTHROPIC_API_KEY) return [];
  const week = weekOf();
  return dbCached<ThemeRule[]>(
    `theme-ideas:${week}`,
    async () => {
      try {
        const client = new Anthropic();
        const response = await client.beta.messages.create({
          model: MODEL,
          max_tokens: 16000,
          output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
          betas: ["server-side-fallback-2026-07-01"],
          fallbacks: "default",
          system: SYSTEM,
          messages: [{ role: "user", content: `Existing themes:\n${THEMES.map((t) => `- ${t.title}`).join("\n")}\n\nPropose 5 new themes for the week of ${week}.` }],
        });
        if (response.stop_reason === "refusal") return [];
        const text = response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
        const parsed = JSON.parse(text) as { themes: (Omit<ThemeRule, "id"> & { look: string })[] };
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
