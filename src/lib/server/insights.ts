import type { SupabaseClient } from "@supabase/supabase-js";
import type { ExploreMover } from "../explore/movers";
import type { Database } from "../supabase/database.types";
import { aiEnabled, aiJson } from "./ai";
import { dbCached } from "./api-cache";
import { exploreMarket } from "./explore";

/**
 * Home's daily insights, written by AI (OpenAI, see ai.ts) once a day from the prices Dexora stores and saved
 * (the same text for everyone, so it's cheap and never makes the app wait):
 * - `briefing`: "Today in the hobby", two or three plain sentences on what's moving;
 * - `reasons`: one short line per highlighted card (Card of the day, Heating up, Cooling off),
 *   keyed by product id, saying what the numbers show.
 * The AI only ever sees our own figures and is told not to invent any. Without
 * OPENAI_API_KEY (set in Vercel) there are simply no insights.
 */
export interface MarketStory {
  /** Six to eight words, e.g. "Vintage is waking up". */
  headline: string;
  /** One figure, e.g. "+14%" or "$1,420". */
  stat: string;
  tone: "up" | "down" | "flat";
  /** The card it's about (one of the given ids), for its picture and link. */
  cardId: string | null;
}

export interface MarketInsights {
  day: string;
  briefing: string | null;
  reasons: Record<string, string>;
  /** "Today in the hobby" as three swipeable stories. */
  stories?: MarketStory[];
}

const HOUR = 60 * 60 * 1000;

const SYSTEM = `You write the daily market notes for Dexora, a Pokémon card collection app.
You get today's figures from Dexora's own price data as JSON. Use only those figures: never invent prices, sales, news, reasons or events that the data doesn't show. If the data doesn't say why something moved, describe the move (how far, over what time, at what price) rather than guessing a cause.
Write for collectors in plain, warm, confident English. No hype words, no emojis, no investment advice; never tell anyone to buy or sell.
"briefing": two or three short sentences (at most 60 words) on the day's clearest patterns across the lists, for example an era or kind of product moving together, or a standout card. Name cards and sets as given.
"reasons": for each card listed under "highlights", one line of at most 14 words explaining its move from its own figures (for example its 24-hour and 7-day change and price). Use the card's id exactly as given.
"stories": exactly three short stories for the day, each a different angle (for example a standout riser, a group or era moving together, a notable fall or sealed). Each has a "headline" of 3 to 8 words in sentence case (a capital first letter, capitals for names of Pokémon and sets) with no figures in it, a "stat" that is one figure taken from the data (a percent like "+14%" or "−8%", or a price like "$1,420"), a "tone" ("up", "down" or "flat") matching the stat, and the "cardId" of the card it's about, copied exactly from the data.`;

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["briefing", "reasons", "stories"],
  properties: {
    briefing: { type: "string" },
    stories: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["headline", "stat", "tone", "cardId"],
        properties: {
          headline: { type: "string" },
          stat: { type: "string" },
          tone: { type: "string", enum: ["up", "down", "flat"] },
          cardId: { type: "string" },
        },
      },
    },
    reasons: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "line"],
        properties: { id: { type: "string" }, line: { type: "string" } },
      },
    },
  },
};

/** One mover as compact facts for the prompt. */
function fact(m: ExploreMover) {
  return {
    id: m.product.id,
    name: m.product.name,
    set: m.product.setName ?? null,
    kind: m.product.kind ?? null,
    price: m.market,
    change24hPct: m.change24hPct ?? null,
    change7dPct: m.change7dPct,
    change30dPct: m.change30dPct,
  };
}

/** Today's insights: saved for the day, written on the first ask. */
export async function marketInsights(admin: SupabaseClient<Database>): Promise<MarketInsights> {
  const day = new Date().toISOString().slice(0, 10);
  const empty: MarketInsights = { day, briefing: null, reasons: {} };
  if (!aiEnabled()) return empty;
  return dbCached<MarketInsights>(
    `insights-v3:${day}`,
    async () => {
      const market = await exploreMarket(admin);
      // The cards Home highlights: Card of the day (today's top riser, else the week's), the
      // week's top risers (Heating up) and biggest fallers (Cooling off).
      const highlights = [...market.today.slice(0, 1), ...market.trending.slice(0, 5), ...market.drops.slice(0, 5)];
      if (!highlights.length) return empty;
      const data = {
        date: day,
        highlights: highlights.map(fact),
        todaysRisers: market.today.slice(0, 5).map(fact),
        weeksRisers: market.trending.slice(0, 10).map(fact),
        weeksFallers: market.drops.slice(0, 8).map(fact),
        risersByEra: {
          modern: market.eras.modern.slice(0, 5).map(fact),
          midEra: market.eras.midEra.slice(0, 5).map(fact),
          vintage: market.eras.vintage.slice(0, 5).map(fact),
        },
        hotSealed: market.hotSealed.slice(0, 5).map(fact),
      };
      try {
        const known = new Set([...highlights, ...market.today, ...market.trending, ...market.drops, ...market.eras.modern, ...market.eras.midEra, ...market.eras.vintage, ...market.hotSealed].map((h) => h.product.id));
        return await write(day, data, new Set(highlights.map((h) => h.product.id)), known);
      } catch (e) {
        console.error("insights", e);
        return empty;
      }
    },
    // A good day is kept until tomorrow; nothing written (no data, or an error) is tried again soon.
    (v) => (v.briefing ? 26 * HOUR : 0),
  );
}

const capitalise = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

async function write(day: string, data: unknown, ids: Set<string>, known: Set<string>): Promise<MarketInsights> {
  const parsed = await aiJson<{ briefing: string; reasons: { id: string; line: string }[]; stories: MarketStory[] }>("market_notes", SYSTEM, `Today's figures:\n${JSON.stringify(data)}`, SCHEMA);
  if (!parsed) return { day, briefing: null, reasons: {} };
  const reasons: Record<string, string> = {};
  // Only lines for cards we asked about, kept short.
  for (const r of parsed.reasons ?? []) if (ids.has(r.id) && r.line.trim()) reasons[r.id] = r.line.trim().slice(0, 140);
  const briefing = parsed.briefing?.trim() ? parsed.briefing.trim().slice(0, 500) : null;
  const stories = (parsed.stories ?? [])
    .filter((st) => st.headline?.trim() && st.stat?.trim())
    .slice(0, 3)
    .map((st) => ({
      headline: capitalise(st.headline.trim().slice(0, 60)),
      stat: st.stat.trim().slice(0, 12),
      tone: (["up", "down", "flat"] as const).includes(st.tone) ? st.tone : "flat",
      cardId: st.cardId && known.has(st.cardId) ? st.cardId : null,
    }));
  return { day, briefing, reasons, stories };
}
