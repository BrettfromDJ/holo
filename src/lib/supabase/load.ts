import type { SupabaseClient } from "@supabase/supabase-js";
import { DEFAULT_PREFERENCES, holdingKey, priceKey, type CollectionData, type PricePoint } from "../types";
import type { Database, HoldingRow } from "./database.types";
import { identityFromHolding, priceFromRow, productFromRow, transactionFromRow, watchFromRow } from "./mappers";

type Client = SupabaseClient<Database>;

/** Supabase returns at most 1000 rows per request; page through larger sets. */
async function all<T>(query: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>): Promise<T[]> {
  const out: T[] = [];
  const size = 1000;
  for (let from = 0; ; from += size) {
    const { data, error } = await query(from, from + size - 1);
    if (error) throw error;
    out.push(...(data ?? []));
    if (!data || data.length < size) break;
  }
  return out;
}

/**
 * Load one user's collection into the engine's `CollectionData` shape. Works
 * with a user-scoped client (RLS filters rows) or the service-role client
 * (pass `userId` to filter explicitly).
 */
export async function loadCollection(client: Client, userId?: string): Promise<CollectionData & { holdingRows: HoldingRow[] }> {
  const scope = <Q extends { eq: (col: string, v: string) => Q }>(q: Q) => (userId ? q.eq("user_id", userId) : q);

  const [holdingRows, txRows, watchRows, prefRows] = await Promise.all([
    all<HoldingRow>((a, b) => scope(client.from("holdings").select("*")).range(a, b)),
    all<Database["public"]["Tables"]["transactions"]["Row"]>((a, b) => scope(client.from("transactions").select("*")).order("created_at").range(a, b)),
    all<Database["public"]["Tables"]["watchlist_items"]["Row"]>((a, b) => scope(client.from("watchlist_items").select("*")).range(a, b)),
    all<Database["public"]["Tables"]["user_preferences"]["Row"]>((a, b) => scope(client.from("user_preferences").select("*")).range(a, b)),
  ]);

  const holdingsById = new Map(holdingRows.map((h) => [h.id, h]));
  const productIds = [...new Set([...holdingRows.map((h) => h.product_id), ...watchRows.map((w) => w.product_id)])];

  const data: CollectionData = {
    products: {},
    transactions: txRows.flatMap((t) => {
      const h = holdingsById.get(t.holding_id);
      return h ? [transactionFromRow(t, h)] : [];
    }),
    watchlist: watchRows.map(watchFromRow),
    prices: {},
    history: {},
    manualValues: {},
    preferences: prefRows[0]
      ? {
          currency: "USD",
          defaultView: prefRows[0].default_view,
          chartRange: prefRows[0].chart_range,
          monthlyBudget: prefRows[0].monthly_budget == null ? null : Number(prefRows[0].monthly_budget),
        }
      : DEFAULT_PREFERENCES,
  };

  for (const h of holdingRows) {
    if (h.manual_value !== null && h.manual_value_date) {
      data.manualValues[holdingKey(identityFromHolding(h))] = { value: Number(h.manual_value), date: h.manual_value_date };
    }
  }

  if (productIds.length) {
    const chunks: string[][] = [];
    for (let i = 0; i < productIds.length; i += 200) chunks.push(productIds.slice(i, i + 200));
    for (const ids of chunks) {
      const [products, prices, snaps] = await Promise.all([
        all<Database["public"]["Tables"]["products"]["Row"]>((a, b) => client.from("products").select("*").in("id", ids).range(a, b)),
        all<Database["public"]["Tables"]["product_prices"]["Row"]>((a, b) => client.from("product_prices").select("*").in("product_id", ids).range(a, b)),
        all<Database["public"]["Tables"]["price_snapshots"]["Row"]>((a, b) =>
          client.from("price_snapshots").select("*").in("product_id", ids).order("snapshot_date").range(a, b),
        ),
      ]);
      for (const p of products) data.products[p.id] = productFromRow(p);
      for (const p of prices) {
        const np = priceFromRow(p);
        data.prices[priceKey(np.productId, np.printing)] = np;
      }
      const byKey = new Map<string, Map<string, number>>();
      for (const s of snaps) {
        const key = priceKey(s.product_id, s.printing === "" ? null : s.printing);
        const m = byKey.get(key) ?? new Map<string, number>();
        m.set(s.snapshot_date, Number(s.market_price));
        byKey.set(key, m);
      }
      for (const [key, m] of byKey) {
        const points: PricePoint[] = [...m.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([date, price]) => ({ date, price }));
        data.history[key] = points;
      }
    }
  }

  return { ...data, holdingRows };
}
