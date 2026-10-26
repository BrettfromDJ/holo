import { NextResponse } from "next/server";
import type { ExploreGame } from "@/lib/explore/types";
import { EXPLORE_CACHE, setFromRow } from "@/lib/server/explore";
import { getAdminSupabase } from "@/lib/supabase/server";

/** GET /api/explore — brands and every set in the stored catalog, newest first. */
export async function GET() {
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Explore needs Supabase to be configured." } }, { status: 503 });
  const [{ data, error }, { data: gameRows }] = await Promise.all([
    admin.from("catalog_sets").select("*").order("release_date", { ascending: false, nullsFirst: false }).limit(6000),
    admin.from("catalog_games").select("*").order("sort"),
  ]);
  if (error) {
    const missing = /catalog_sets/.test(error.message);
    return NextResponse.json(
      { error: { message: missing ? "Run supabase/migrations/20261027000000_catalog_sets.sql in Supabase to enable Explore." : error.message } },
      { status: missing ? 503 : 500 },
    );
  }
  const sets = (data ?? []).map(setFromRow);

  // Brands come from catalog_games when available; otherwise from the set list.
  const games = new Map<string, ExploreGame>();
  for (const g of gameRows ?? []) games.set(g.slug, { slug: g.slug, name: g.name, logoUrl: g.logo_url ?? g.image_url, sets: 0, loadedSets: 0, cardCount: g.card_count });
  for (const s of sets) {
    const g = games.get(s.gameSlug) ?? { slug: s.gameSlug, name: s.gameName, logoUrl: null, sets: 0, loadedSets: 0, cardCount: null };
    g.sets++;
    if (s.loaded) g.loadedSets++;
    games.set(s.gameSlug, g);
  }
  const ordered = [...games.values()].filter((g) => g.sets > 0);
  if (!gameRows?.length) ordered.sort((a, b) => (a.slug === "pokemon" ? -1 : b.slug === "pokemon" ? 1 : a.name.localeCompare(b.name)));

  // Never cache an empty or barely-started catalog, so the first sync shows up right away.
  const cache = sets.some((s) => s.loaded) ? EXPLORE_CACHE : "no-store";
  return NextResponse.json({ games: ordered, sets }, { headers: { "cache-control": cache } });
}
