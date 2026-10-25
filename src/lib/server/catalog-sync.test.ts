import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

const tcg = {
  catalogGameList: vi.fn(async () => [{ slug: "pokemon", name: "Pokemon" }]),
  gameSetsPage: vi.fn(async () => ({
    sets: [
      { id: 1, slug: "new-set", name: "New Set", game_name: "Pokemon", abbreviation: null, release_date: "2026-09-01T00:00:00Z", card_count: 3, image_url: null, set_icon_url: null },
      { id: 2, slug: "old-set", name: "Old Set", game_name: "Pokemon", abbreviation: null, release_date: "2020-01-01T00:00:00Z", card_count: 3, image_url: null, set_icon_url: null },
    ],
    hasMore: false,
  })),
  setProductsPage: vi.fn(async (set: { slug: string }) => ({
    products: [{ id: `tcgapi:${set.slug}-1`, source: "tcgapi", externalId: "1", name: "Card", setName: set.slug, setId: set.slug, number: "1", rarity: null, productType: "Cards", kind: "single", imageUrl: null, tcgplayerId: null, tcgplayerUrl: null }],
    prices: [{ productId: `tcgapi:${set.slug}-1`, printing: "Holofoil", market: 5, low: null, change24hPct: null, change7dPct: null, change30dPct: null, updatedAt: null, fetchedAt: null, source: "tcgapi", status: "stale" }],
    hasMore: false,
  })),
};
vi.mock("../pricing/tcgapi", () => tcg);

/** Minimal chainable stand-in for the Supabase query builder. */
function fakeAdmin() {
  const db: Record<string, Record<string, unknown>[]> = { catalog_sets: [], products: [], product_prices: [], price_snapshots: [] };
  const writes: { table: string; op: string; rows: unknown }[] = [];
  const from = (table: string) => {
    let rows = () => db[table];
    const q = {
      select: () => q,
      order: () => q,
      limit: () => q,
      in: () => q,
      eq: (col: string, val: unknown) => {
        const pending = writes[writes.length - 1];
        if (pending?.op === "update" && pending.table === table) {
          for (const r of db[table]) if (r[col] === val) Object.assign(r, pending.rows);
        }
        return q;
      },
      upsert: (input: Record<string, unknown>[], opts?: { ignoreDuplicates?: boolean }) => {
        writes.push({ table, op: "upsert", rows: input });
        const key = table === "catalog_sets" ? "slug" : table === "products" ? "id" : "product_id";
        for (const r of input) {
          const i = db[table].findIndex((x) => x[key] === r[key]);
          if (i < 0) db[table].push({ ...r });
          else if (!opts?.ignoreDuplicates) db[table][i] = { ...db[table][i], ...r };
        }
        return Promise.resolve({ error: null });
      },
      update: (patch: Record<string, unknown>) => {
        writes.push({ table, op: "update", rows: patch });
        return q;
      },
      then: (resolve: (v: { data: unknown; error: null }) => void) => {
        const data = table === "catalog_sets" ? [...rows()].sort((a, b) => (a.products_synced_at ? 1 : 0) - (b.products_synced_at ? 1 : 0) || String(b.release_date).localeCompare(String(a.release_date))) : rows();
        rows = () => db[table];
        resolve({ data, error: null });
      },
    };
    return q;
  };
  return { admin: { from } as never, db, writes };
}

describe("syncCatalog", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("lists sets, then loads products for unloaded sets newest first", async () => {
    const { syncCatalog } = await import("./catalog-sync");
    const { admin, db } = fakeAdmin();
    const res = await syncCatalog(admin, { maxCalls: 10 });
    expect(res.stoppedBecause).toBe("done");
    expect(res.setsListed).toBe(2);
    expect(res.setsSynced).toEqual(["new-set", "old-set"]);
    expect(res.calls).toBe(3);
    expect(db.products).toHaveLength(2);
    expect(db.catalog_sets.every((s) => s.products_synced_at)).toBe(true);
  });

  it("stops at the call budget and leaves the rest for tomorrow", async () => {
    const { syncCatalog } = await import("./catalog-sync");
    const { admin } = fakeAdmin();
    const res = await syncCatalog(admin, { maxCalls: 2 });
    expect(res.stoppedBecause).toBe("budget");
    expect(res.setsSynced).toEqual(["new-set"]);
  });

  it("never overwrites a product that already exists (e.g. a corrected type)", async () => {
    const { syncCatalog } = await import("./catalog-sync");
    const { admin, db } = fakeAdmin();
    db.products.push({ id: "tcgapi:new-set-1", kind: "sealed" });
    await syncCatalog(admin, { maxCalls: 10 });
    expect(db.products.find((p) => p.id === "tcgapi:new-set-1")?.kind).toBe("sealed");
  });
});
