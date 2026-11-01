import { describe, expect, it } from "vitest";
import { effectiveTransactions } from "./finance/ledger";
import {
  EMPTY_MEMORY,
  REUSE_DATE_MS,
  editedIdentity,
  gradesFor,
  liveEntries,
  moveKeyed,
  moveSlabKeyed,
  purchaseDefaults,
  rememberPurchase,
  removalEntry,
  removedMessage,
  renameEntries,
  restoreEntry,
  voidEntry,
} from "./holding-actions";
import { holdingKey, type HoldingIdentity, type Transaction } from "./types";

const raw: HoldingIdentity = { productId: "tcgapi:1", printing: "Holofoil", condition: "Near Mint", grade: null };
const slab: HoldingIdentity = { productId: "tcgapi:1", printing: "Holofoil", condition: "Near Mint", grade: { company: "PSA", grade: "10" } };

let n = 0;
function tx(over: Partial<Transaction>): Transaction {
  n += 1;
  return { ...raw, id: `t${n}`, type: "purchase", date: "2026-01-01", quantity: 1, unitPrice: 10, fees: 0, shipping: 0, tax: 0, createdAt: `2026-01-01T00:00:${String(n).padStart(2, "0")}Z`, ...over };
}
/** Saves a new entry like a repository would. */
function save(all: Transaction[], t: Omit<Transaction, "id" | "createdAt">): Transaction[] {
  return [...all, tx(t)];
}

describe("holding key", () => {
  it("matches the app's HoldingIdentity.key", () => {
    expect(holdingKey(raw)).toBe("tcgapi:1|Holofoil|Near Mint|");
    expect(holdingKey(slab)).toBe("tcgapi:1|Holofoil|Near Mint|PSA 10");
    expect(holdingKey({ ...raw, printing: null, condition: "Sealed" })).toBe("tcgapi:1||Sealed|");
  });
});

describe("remove", () => {
  it("is a negative adjustment at no price, with the reason as its note", () => {
    const r = removalEntry(raw, 2, "Opened", "2026-02-01");
    expect(r).toMatchObject({ type: "adjustment", quantity: -2, unitPrice: 0, notes: "Opened", date: "2026-02-01", grade: null });
    expect(removedMessage(2, "Gave away")).toBe("Removed 2 · gave away");
  });

  it("undo voids the removal", () => {
    let all = [tx({ quantity: 3 })];
    all = save(all, removalEntry(raw, 1, "Lost", "2026-02-01"));
    const removal = all[all.length - 1];
    all = save(all, voidEntry(removal));
    expect(liveEntries(all, holdingKey(raw)).map((t) => t.id)).toEqual([all[0].id]);
  });
});

describe("delete from collection and undo", () => {
  it("voids every live entry and restores them with their edited values", () => {
    const buy = tx({ quantity: 2, unitPrice: 5 });
    const sale = tx({ type: "sale", quantity: 1, unitPrice: 9 });
    const other = tx({ ...slab, quantity: 1 });
    let all = [buy, sale, other];
    // An earlier edit to the purchase: the restore must bring back the edited values.
    all = save(all, { ...raw, type: "correction", correctsId: buy.id, date: "2026-01-02", quantity: 3, unitPrice: 6, fees: 1, shipping: 0, tax: 0, notes: "Edited" });
    const live = liveEntries(all, holdingKey(raw));
    expect(live.map((t) => t.id).sort()).toEqual([buy.id, sale.id].sort());

    for (const t of live) all = save(all, voidEntry(t));
    expect(liveEntries(all, holdingKey(raw))).toEqual([]);
    expect(liveEntries(all, holdingKey(slab)).map((t) => t.id)).toEqual([other.id]);

    for (const t of live) all = save(all, restoreEntry(t));
    const back = liveEntries(all, holdingKey(raw));
    expect(back.find((t) => t.id === buy.id)).toMatchObject({ quantity: 3, unitPrice: 6, fees: 1, date: "2026-01-02" });
    expect(back.find((t) => t.id === sale.id)).toMatchObject({ quantity: 1, unitPrice: 9 });
  });

  it("restores a removal with its negative quantity", () => {
    const r = tx({ type: "adjustment", quantity: -1, unitPrice: 0 });
    let all = [tx({ quantity: 2 }), r];
    all = save(all, voidEntry(r));
    all = save(all, restoreEntry(r));
    expect(effectiveTransactions(all).find((t) => t.id === r.id)?.quantity).toBe(-1);
  });
});

describe("edit details", () => {
  const choice = { sealed: false, printing: "Holofoil", graded: false, company: "PSA", grade: "10", condition: "Lightly Played" as const };

  it("builds the new copy like the app", () => {
    expect(editedIdentity(raw, choice)).toEqual({ ...raw, condition: "Lightly Played" });
    expect(editedIdentity({ ...raw, condition: "Lightly Played" }, { ...choice, graded: true, company: "BGS", grade: "9.5" })).toEqual({ ...raw, grade: { company: "BGS", grade: "9.5" } });
    expect(editedIdentity(slab, { ...choice, graded: false })).toEqual({ ...raw, condition: "Lightly Played" });
    expect(editedIdentity({ ...raw, condition: "Sealed" }, { ...choice, sealed: true, printing: null, graded: true })).toEqual({ ...raw, printing: null, condition: "Sealed" });
  });

  it("moves every entry of the copy, corrections included", () => {
    const a = tx({});
    const fix = tx({ type: "correction", correctsId: a.id, quantity: 2 });
    const b = tx({ ...slab });
    const out = renameEntries([a, fix, b], holdingKey(raw), slab);
    expect(out.every((t) => holdingKey(t) === holdingKey(slab))).toBe(true);
    expect(out[0].id).toBe(a.id);
  });

  it("offers half grades only for BGS and CGC, highest first", () => {
    expect(gradesFor("PSA")).toEqual(["10", "9", "8", "7", "6", "5", "4", "3", "2", "1"]);
    expect(gradesFor("BGS").slice(0, 4)).toEqual(["10", "9.5", "9", "8.5"]);
  });

  it("moves certs and bumpers to a slab's new key unless it has its own", () => {
    const certs = { [holdingKey(slab)]: "123" };
    const nine = { ...slab, grade: { company: "PSA", grade: "9" } };
    expect(moveSlabKeyed(certs, slab, nine)).toEqual({ [holdingKey(nine)]: "123" });
    // A raw copy keeps nothing; the map is untouched.
    expect(moveSlabKeyed(certs, slab, raw)).toBe(certs);
    expect(moveKeyed({ a: 1, b: 2 }, "a", "b")).toEqual({ a: 1, b: 2 });
    expect(moveKeyed({ a: 1 }, "x", "b")).toEqual({ a: 1 });
  });
});

describe("remembered purchase details", () => {
  const opts = { sealed: false, today: "2026-03-10", now: 1_000_000_000_000, companies: ["PSA", "BGS", "CGC"] as const };

  it("starts fresh with nothing remembered", () => {
    expect(purchaseDefaults(EMPTY_MEMORY, opts)).toEqual({ source: "", condition: "Near Mint", graded: false, company: "PSA", grade: "10", date: "2026-03-10" });
  });

  it("remembers source, condition and grade; the date only for 6 hours", () => {
    const mem = rememberPurchase(EMPTY_MEMORY, { sealed: false, source: " eBay ", date: "2026-03-08", graded: false, company: "PSA", grade: "10", condition: "Lightly Played" }, opts.now);
    expect(purchaseDefaults(mem, opts)).toMatchObject({ source: "eBay", condition: "Lightly Played", graded: false, date: "2026-03-08" });
    expect(purchaseDefaults(mem, { ...opts, now: opts.now + REUSE_DATE_MS + 1 }).date).toBe("2026-03-10");

    const slabMem = rememberPurchase(mem, { sealed: false, source: "Show", date: "2026-03-08", graded: true, company: "BGS", grade: "9.5", condition: "Near Mint" }, opts.now);
    // The raw condition picked before is kept for the next raw card.
    expect(purchaseDefaults(slabMem, opts)).toMatchObject({ graded: true, company: "BGS", grade: "9.5", condition: "Lightly Played" });
    // Sealed products are never graded and keep "Sealed".
    expect(purchaseDefaults(slabMem, { ...opts, sealed: true })).toMatchObject({ graded: false, condition: "Sealed" });
  });

  it("a sealed save leaves the card details alone", () => {
    const mem = { ...EMPTY_MEMORY, graded: true, company: "CGC" };
    expect(rememberPurchase(mem, { sealed: true, source: "Store", date: "2026-03-09", graded: false, company: "PSA", grade: "10", condition: "Sealed" }, 5)).toMatchObject({ graded: true, company: "CGC", source: "Store", savedAt: 5 });
  });
});
