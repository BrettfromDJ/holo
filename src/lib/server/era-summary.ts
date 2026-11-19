import type { SupabaseClient } from "@supabase/supabase-js";
import { summarizeEras, type EraMove, type EraRow, type EraSummary } from "../explore/era-summary";
import { isCodeCard, isOversized } from "../explore/movers";
import type { Database, ProductRow } from "../supabase/database.types";
import { dbCached } from "./api-cache";
import { withPrices } from "./explore";
import { selectAll } from "./paging";

const HOUR = 60 * 60 * 1000;

type PriceJoin = {
  product_id: string;
  market_price: number | string | null;
  change_24h_pct: number | string | null;
  change_7d_pct: number | string | null;
  products: { kind: string; set_id: string | null; name: string; rarity: string | null; product_type: string | null } | null;
};

const num = (v: number | string | null): number | null => (v === null || v === undefined ? null : Number(v));

/**
 * The three eras' summaries (see `era-summary.ts`), from our stored prices only (no TCG API).
 * Worked out a few times a day and saved, so Home never waits on it.
 */
export async function eraSummaries(admin: SupabaseClient<Database>): Promise<EraSummary[]> {
  const hour = new Date().toISOString().slice(0, 13);
  return dbCached<EraSummary[]>(
    `era-summary:${hour.slice(0, 11)}${Math.floor(Number(hour.slice(11)) / 6)}`,
    async () => {
      // English Pokémon sets and their release dates.
      const sets = await selectAll<{ slug: string; game_name: string; release_date: string | null }>(
        (from, to) => admin.from("catalog_sets").select("slug, game_name, release_date").order("slug").range(from, to),
        20_000,
      );
      const released = new Map(sets.filter((s) => /pok/i.test(s.game_name) && !/japan/i.test(s.game_name)).map((s) => [s.slug, s.release_date]));
      // Every priced single from $5 with a change, with its card's set.
      const prices = await selectAll<PriceJoin>(
        (from, to) =>
          admin
            .from("product_prices")
            .select("product_id, market_price, change_24h_pct, change_7d_pct, products!inner(kind, set_id, name, rarity, product_type)")
            .eq("products.kind", "single")
            .gte("market_price", 5)
            .or("change_7d_pct.not.is.null,change_24h_pct.not.is.null")
            .order("product_id")
            .range(from, to) as unknown as PromiseLike<{ data: PriceJoin[] | null; error: { message: string } | null }>,
        80_000,
      );
      const seen = new Set<string>();
      const rows: EraRow[] = [];
      for (const p of prices) {
        const prod = p.products;
        if (!prod?.set_id || !released.has(prod.set_id) || seen.has(p.product_id)) continue;
        const pr = { name: prod.name, rarity: prod.rarity, productType: prod.product_type };
        if (isCodeCard(pr) || isOversized(pr)) continue;
        const market = num(p.market_price);
        if (market === null) continue;
        seen.add(p.product_id);
        rows.push({ id: p.product_id, market, change24h: num(p.change_24h_pct), change7d: num(p.change_7d_pct), releaseDate: released.get(prod.set_id) ?? null });
      }
      const summed = summarizeEras(rows);
      // The moves' cards, with pictures and prices.
      const ids = summed.flatMap((e) => e.moveIds.map((m) => m.id));
      const { data: productRows } = ids.length ? await admin.from("products").select("*").in("id", ids) : { data: [] };
      const priced = await withPrices(admin, (productRows ?? []) as ProductRow[]);
      const byId = new Map(priced.map((p) => [p.product.id, p]));
      return summed.map(({ moveIds, ...e }) => ({
        ...e,
        moves: moveIds.flatMap((m): EraMove[] => {
          const p = byId.get(m.id);
          return p ? [{ ...p, changePct: m.changePct }] : [];
        }),
      }));
    },
    // Nothing tracked yet (a fresh table): try again within the hour.
    (v) => (v.some((e) => e.tracked > 0) ? 7 * HOUR : HOUR),
  );
}
