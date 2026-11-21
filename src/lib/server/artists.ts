import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { artistSetKey, numberKey } from "../artists";
import type { Database } from "../supabase/database.types";

/**
 * Who drew each card. Our card source (TCG API) doesn't say; the free Pokémon TCG API
 * (pokemontcg.io) does for nearly every English card. Once per set: find its set there by code or
 * name, read every card's number and artist (one or two requests), and write the artist onto our
 * cards with the same number. New sets are picked up by the nightly run; nothing is paid for.
 */
const BASE = "https://api.pokemontcg.io/v2";

type PtcgSet = { id: string; name: string; ptcgoCode?: string; total?: number };

async function ptcg<T>(path: string): Promise<T> {
  const headers: Record<string, string> = { accept: "application/json" };
  if (process.env.POKEMONTCG_API_KEY) headers["x-api-key"] = process.env.POKEMONTCG_API_KEY;
  const res = await fetch(`${BASE}${path}`, { headers, signal: AbortSignal.timeout(30_000) });
  if (!res.ok) throw new Error(`pokemontcg.io ${res.status}`);
  return (await res.json()) as T;
}

/** Fill artists for sets not done yet, within `budgetMs`. */
export async function syncArtists(admin: SupabaseClient<Database>, budgetMs = 240_000) {
  const started = Date.now();
  const { data: sets } = await admin
    .from("catalog_sets")
    .select("slug, name, abbreviation, game_name")
    .is("artists_synced_at", null)
    .ilike("game_name", "%pok%")
    .order("release_date", { ascending: false })
    .limit(400);
  const ours = (sets ?? []).filter((s) => !/japan/i.test(s.game_name ?? ""));
  if (!ours.length) return { sets: 0, cards: 0, unmatched: 0 };

  const theirs = (await ptcg<{ data: PtcgSet[] }>("/sets?pageSize=250&select=id,name,ptcgoCode,total")).data;
  const byKey = new Map(theirs.map((s) => [artistSetKey(s.name), s]));
  const byCode = new Map(theirs.filter((s) => s.ptcgoCode).map((s) => [s.ptcgoCode!.toUpperCase(), s]));

  let done = 0, cards = 0, unmatched = 0;
  for (const set of ours) {
    if (Date.now() - started > budgetMs) break;
    const match = byKey.get(artistSetKey(set.name)) ?? (set.abbreviation ? byCode.get(set.abbreviation.toUpperCase()) : undefined);
    if (!match) {
      // Not on pokemontcg.io (yet): left to try again another night.
      unmatched++;
      continue;
    }
    const artists = new Map<string, string>();
    for (let page = 1; page <= 4; page++) {
      const body = await ptcg<{ data: { number: string; artist?: string }[]; totalCount: number }>(
        `/cards?q=set.id:${encodeURIComponent(match.id)}&select=number,artist&pageSize=250&page=${page}`,
      );
      for (const c of body.data) {
        const k = numberKey(c.number);
        if (k && c.artist) artists.set(k, c.artist.trim());
      }
      if (page * 250 >= body.totalCount) break;
    }
    const { data: products } = await admin.from("products").select("id, number").eq("set_id", set.slug).eq("kind", "single");
    const byArtist = new Map<string, string[]>();
    for (const p of products ?? []) {
      const a = artists.get(numberKey(p.number) ?? "");
      if (a) byArtist.set(a, [...(byArtist.get(a) ?? []), p.id]);
    }
    for (const [artist, ids] of byArtist) {
      for (let i = 0; i < ids.length; i += 200) {
        await admin.from("products").update({ artist }).in("id", ids.slice(i, i + 200));
      }
      cards += ids.length;
    }
    await admin.from("catalog_sets").update({ artists_synced_at: new Date().toISOString() }).eq("slug", set.slug);
    done++;
  }
  return { sets: done, cards, unmatched };
}
