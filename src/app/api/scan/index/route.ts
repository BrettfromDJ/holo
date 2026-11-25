import { NextResponse } from "next/server";
import { isCodeCard, isOversized } from "@/lib/explore/movers";
import { selectAll } from "@/lib/server/paging";
import { getAdminSupabase } from "@/lib/supabase/server";

/**
 * GET /api/scan/index — every English Pokémon single, packed small, for the phone scanner to keep
 * on the phone: once it reads a card's name and number it finds the card there in milliseconds
 * instead of asking the server (the round trip was most of a scan's time). Built from our own
 * catalog (no TCG API cost) and cached a day at Vercel's edge; the phone refreshes daily.
 *
 * Shape (repeated strings go in tables, each card points into them):
 *   { v: 1, built, sets: [[slug, name]], dirs: [url prefix], rarities: [...], printings: ["Normal|Holofoil"],
 *     cards: [[id without "tcgapi:", name, number, set, dir, file, rarity, printings]] }
 */
export const maxDuration = 60;

type Row = { id: string; name: string; number: string | null; set_id: string | null; set_name: string | null; image_url: string | null; rarity: string | null; printings: string[] | null; product_type: string | null };

export async function GET() {
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Not configured." } }, { status: 503 });

  const { data: setRows, error } = await admin.from("catalog_sets").select("slug, name, game_name").ilike("game_name", "%pok%");
  if (error) return NextResponse.json({ error: { message: error.message } }, { status: 500 });
  const englishSets = (setRows ?? []).filter((s) => !/japan/i.test(s.game_name));
  const slugs = englishSets.map((s) => s.slug);
  if (!slugs.length) return NextResponse.json({ v: 1, built: new Date().toISOString(), sets: [], dirs: [], rarities: [], printings: [], cards: [] });

  const rows: Row[] = [];
  for (let i = 0; i < slugs.length; i += 150) {
    const chunk = slugs.slice(i, i + 150);
    rows.push(
      ...(await selectAll<Row>((from, to) =>
        admin.from("products").select("id, name, number, set_id, set_name, image_url, rarity, printings, product_type")
          .eq("source", "tcgapi").eq("kind", "single").in("set_id", chunk).order("id").range(from, to),
      100_000)),
    );
  }

  const table = <T,>() => {
    const list: T[] = [];
    const at = new Map<T, number>();
    return { list, index: (v: T) => { let n = at.get(v); if (n === undefined) { n = list.length; list.push(v); at.set(v, n); } return n; } };
  };
  const sets = table<string>(), dirs = table<string>(), rarities = table<string>(), printings = table<string>();
  const setNames = new Map(englishSets.map((s) => [s.slug, s.name]));
  const cards: (string | number)[][] = [];
  for (const r of rows) {
    const product = { name: r.name, setName: r.set_name, number: r.number, rarity: r.rarity, productType: r.product_type };
    if (isOversized(product) || isCodeCard({ name: r.name, productType: r.product_type, rarity: r.rarity })) continue;
    const url = r.image_url ?? "";
    const cut = url.lastIndexOf("/") + 1;
    cards.push([
      r.id.replace(/^tcgapi:/, ""),
      r.name,
      r.number ?? "",
      sets.index(r.set_id ?? ""),
      dirs.index(url.slice(0, cut)),
      url.slice(cut),
      rarities.index(r.rarity ?? ""),
      printings.index((r.printings ?? []).join("|")),
    ]);
  }
  return NextResponse.json(
    {
      v: 1,
      built: new Date().toISOString(),
      sets: sets.list.map((slug) => [slug, setNames.get(slug) ?? rows.find((r) => r.set_id === slug)?.set_name ?? ""]),
      dirs: dirs.list,
      rarities: rarities.list,
      printings: printings.list,
      cards,
    },
    { headers: { "cache-control": "public, s-maxage=86400, stale-while-revalidate=86400" } },
  );
}
