import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { isOversized } from "../explore/movers";
import type { ExploreProduct } from "../explore/types";
import type { Database, ProductRow } from "../supabase/database.types";
import { dbCached } from "./api-cache";
import { withPrices } from "./explore";
import { selectAll } from "./paging";

/** Every card one artist drew, priciest first (from our own catalog; saved a day). */
export async function artistCards(admin: SupabaseClient<Database>, name: string): Promise<ExploreProduct[]> {
  const clean = name.trim();
  if (!clean) return [];
  return dbCached<ExploreProduct[]>(
    `artist:${clean.toLowerCase()}`,
    async () => {
      // Exact name, any case (escaping the pattern's wildcards).
      const pattern = clean.replace(/[\\%_]/g, (c) => `\\${c}`);
      const rows = await selectAll<ProductRow>(
        (from, to) => admin.from("products").select("*").eq("kind", "single").ilike("artist", pattern).order("id").range(from, to),
        3000,
      );
      const priced = await withPrices(admin, rows);
      return priced
        .filter((p) => !isOversized(p.product))
        .sort((a, b) => (b.market ?? -1) - (a.market ?? -1));
    },
    (v) => (v.length ? 24 * 60 * 60 * 1000 : 60 * 60 * 1000),
  );
}
