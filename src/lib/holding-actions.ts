/**
 * What the Owned sheet's ⋯ menu writes, as plain data: Remove, Delete from collection, Edit
 * details and their Undo. Ported from the app's CollectionStore (`remove`, `deleteCopy`,
 * `delete`, `sell`, `changeDetails`) and GradingStore (`moveSlab`), so both write the same rows.
 */

import { effectiveTransactions } from "./finance/ledger";
import type { NewTransaction } from "./store/repository";
import { holdingKey, type Condition, type HoldingIdentity, type ISODate, type Transaction } from "./types";

/** Why copies leave without a sale (the app's RemoveSheet reasons). */
export const REMOVE_REASONS = ["Opened", "Lost", "Gave away", "Damaged", "Traded away"] as const;

/** Raw conditions a single can be in (sealed products are always "Sealed"). */
export const RAW_CONDITIONS: Condition[] = ["Near Mint", "Lightly Played", "Moderately Played", "Heavily Played", "Damaged"];

const identityOf = (t: HoldingIdentity): HoldingIdentity => ({ productId: t.productId, printing: t.printing, condition: t.condition, grade: t.grade });

/** One copy's entries as they count now (edits applied, deleted ones gone). */
export function liveEntries(all: Transaction[], key: string): Transaction[] {
  return effectiveTransactions(all).filter((t) => holdingKey(t) === key);
}

/** Copies out without a sale: an adjustment with a negative quantity; its cost is written off. */
export function removalEntry(identity: HoldingIdentity, quantity: number, reason: string, date: ISODate): NewTransaction {
  return { ...identityOf(identity), type: "adjustment", date, quantity: -Math.abs(quantity), unitPrice: 0, fees: 0, shipping: 0, tax: 0, source: null, notes: reason };
}

/** Voids an entry: a correction with quantity 0 (the original stays in the record). */
export function voidEntry(t: Transaction): NewTransaction {
  return { ...identityOf(t), type: "correction", correctsId: t.id, date: t.date, quantity: 0, unitPrice: 0, fees: 0, shipping: 0, tax: 0, notes: "Deleted" };
}

/** Brings a voided entry back: a correction carrying the values it counted with. */
export function restoreEntry(t: Transaction): NewTransaction {
  return {
    ...identityOf(t),
    type: "correction",
    correctsId: t.id,
    date: t.date,
    quantity: t.quantity,
    unitPrice: t.unitPrice,
    fees: t.fees,
    shipping: t.shipping,
    tax: t.tax,
    source: t.source ?? null,
    notes: t.notes ?? null,
  };
}

/** The toast after a removal, as in the app: "Removed 2 · opened". */
export function removedMessage(quantity: number, reason: string): string {
  return `Removed ${Math.abs(quantity)} · ${reason.toLowerCase()}`;
}

/** Grades offered for a company, highest first (BGS and CGC also give half grades). */
export function gradesFor(company: string): string[] {
  const whole = Array.from({ length: 10 }, (_, i) => String(i + 1));
  const all = company === "BGS" || company === "CGC" ? [...whole, "9.5", "8.5", "7.5"] : whole;
  return all.sort((a, b) => Number(b) - Number(a));
}

export interface DetailsChoice {
  sealed: boolean;
  printing: string | null;
  graded: boolean;
  company: string;
  grade: string;
  condition: Condition;
}

/** The copy with the details picked in Edit details (a slab is always Near Mint underneath). */
export function editedIdentity(old: HoldingIdentity, c: DetailsChoice): HoldingIdentity {
  if (c.sealed) return { ...identityOf(old), printing: c.printing, condition: "Sealed", grade: null };
  if (c.graded) return { ...identityOf(old), printing: c.printing, condition: "Near Mint", grade: { company: c.company, grade: c.grade } };
  return { ...identityOf(old), printing: c.printing, condition: c.condition, grade: null };
}

/** Every entry of the old copy (corrections too) now belongs to the new one. */
export function renameEntries(all: Transaction[], oldKey: string, next: HoldingIdentity): Transaction[] {
  return all.map((t) => (holdingKey(t) === oldKey ? { ...t, ...identityOf(next) } : t));
}

/**
 * A per-copy value (cert number, bumper, your own value) follows the copy to its new key,
 * unless the new key already has one. Returns the same object when nothing moves.
 */
export function moveKeyed<T>(map: Record<string, T>, oldKey: string, newKey: string): Record<string, T> {
  if (oldKey === newKey || !(oldKey in map) || newKey in map) return map;
  const next = { ...map, [newKey]: map[oldKey] };
  delete next[oldKey];
  return next;
}

/** Certs and bumpers move only when the new copy is a slab (the app's `moveSlab`). */
export function moveSlabKeyed<T>(map: Record<string, T>, old: HoldingIdentity, next: HoldingIdentity): Record<string, T> {
  return next.grade ? moveKeyed(map, holdingKey(old), holdingKey(next)) : map;
}

/* ---------------------- Remembered purchase details ---------------------- */

/** What the add-purchase form remembers on this device (the app's `holo.add.*` keys). */
export interface PurchaseMemory {
  source: string;
  condition: string;
  graded: boolean;
  company: string;
  grade: string;
  /** The date last picked, and when that purchase was saved (ms). */
  date: ISODate | null;
  savedAt: number;
}

export const EMPTY_MEMORY: PurchaseMemory = { source: "", condition: "", graded: false, company: "PSA", grade: "10", date: null, savedAt: 0 };

/** Logging several buys (a card show): the last date is reused for 6 hours. */
export const REUSE_DATE_MS = 6 * 3600 * 1000;

/** The form's starting values from what was remembered. */
export function purchaseDefaults(mem: PurchaseMemory, opts: { sealed: boolean; today: ISODate; now: number; companies: readonly string[] }) {
  const condition = !opts.sealed && (RAW_CONDITIONS as string[]).includes(mem.condition) ? (mem.condition as Condition) : opts.sealed ? "Sealed" : "Near Mint";
  const reuse = mem.date !== null && opts.now - mem.savedAt < REUSE_DATE_MS;
  return {
    source: mem.source,
    condition,
    graded: !opts.sealed && mem.graded,
    company: opts.companies.includes(mem.company) ? mem.company : "PSA",
    grade: mem.grade || "10",
    // Never in the future.
    date: reuse && mem.date! <= opts.today ? mem.date! : opts.today,
  };
}

/** What to remember after a save. A sealed product leaves the card details as they were. */
export function rememberPurchase(prev: PurchaseMemory, saved: { sealed: boolean; source: string; date: ISODate; graded: boolean; company: string; grade: string; condition: string }, now: number): PurchaseMemory {
  const next: PurchaseMemory = { ...prev, source: saved.source.trim(), date: saved.date, savedAt: now };
  if (!saved.sealed) {
    next.graded = saved.graded;
    if (saved.graded) {
      next.company = saved.company;
      next.grade = saved.grade;
    } else next.condition = saved.condition;
  }
  return next;
}

const MEMORY_KEY = "holo:add:memory";

export function readPurchaseMemory(): PurchaseMemory {
  try {
    const raw = localStorage.getItem(MEMORY_KEY);
    return raw ? { ...EMPTY_MEMORY, ...(JSON.parse(raw) as Partial<PurchaseMemory>) } : EMPTY_MEMORY;
  } catch {
    return EMPTY_MEMORY;
  }
}

export function writePurchaseMemory(mem: PurchaseMemory) {
  try {
    localStorage.setItem(MEMORY_KEY, JSON.stringify(mem));
  } catch {
    // Storage blocked: the form just starts fresh next time.
  }
}
