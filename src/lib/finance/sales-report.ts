import { holdingKey, type HoldingIdentity, type Product, type Transaction } from "../types";
import { acquisitionCost, effectiveTransactions, saleProceeds } from "./ledger";

/**
 * What you sold, matched to what those copies cost, for a year-end summary or an accountant.
 * Copies leave oldest first (FIFO), exactly like the ledger, so the profit here adds up to the
 * realized gain shown everywhere else. A sale that takes copies bought on different days is split
 * into one line per purchase date, the way a tax form lists it. Mirrors the app's
 * `Domain/SalesReport.swift`.
 */
export interface SaleLine {
  /** The sale, plus which of its purchase dates this line covers. */
  id: string;
  saleId: string;
  identity: HoldingIdentity;
  /** yyyy-MM-dd the copies were bought or pulled (null if never recorded). */
  acquired: string | null;
  /** yyyy-MM-dd they were sold. */
  sold: string;
  quantity: number;
  /** What they sold for after the sale's fees, shipping and tax. */
  proceeds: number;
  /** What they cost, extras included. */
  cost: number;
  gain: number;
  /** Held more than a year (the US long-term rule). */
  longTerm: boolean;
  year: number;
}

export interface SalesTotals {
  proceeds: number;
  cost: number;
  gain: number;
  shortTermGain: number;
  longTermGain: number;
  /** Copies sold. */
  quantity: number;
  /** Separate sales (one sale split over several purchase dates counts once). */
  sales: number;
}

const EPS = 1e-9;

interface OpenLot {
  date: string;
  quantity: number;
  unitCost: number;
}

/** Every sale in the log, newest first, split by purchase date. */
export function salesLines(transactions: Transaction[]): SaleLine[] {
  const lots = new Map<string, OpenLot[]>();
  const out: SaleLine[] = [];

  const consume = (key: string, qty: number): [OpenLot, number][] => {
    let remaining = qty;
    const taken: [OpenLot, number][] = [];
    const open = lots.get(key) ?? [];
    for (const lot of open) {
      if (remaining <= EPS) break;
      const take = Math.min(lot.quantity, remaining);
      if (take > EPS) taken.push([{ ...lot }, take]);
      lot.quantity -= take;
      remaining -= take;
    }
    lots.set(
      key,
      open.filter((l) => l.quantity > EPS),
    );
    return taken;
  };

  for (const t of effectiveTransactions(transactions)) {
    const key = holdingKey(t);
    if ((t.type === "purchase" || t.type === "adjustment") && t.quantity > 0) {
      const list = lots.get(key) ?? [];
      list.push({ date: t.date, quantity: t.quantity, unitCost: acquisitionCost(t) / t.quantity });
      lots.set(key, list);
    } else if (t.type === "adjustment" && t.quantity < 0) {
      // Lost or given away: those copies are gone, but nothing was sold.
      consume(key, -t.quantity);
    } else if (t.type === "sale" && t.quantity > 0) {
      const taken = consume(key, t.quantity);
      const perUnit = saleProceeds(t) / t.quantity;
      const identity: HoldingIdentity = { productId: t.productId, printing: t.printing, condition: t.condition, grade: t.grade };
      taken.forEach(([lot, qty], n) => {
        const proceeds = perUnit * qty;
        const cost = lot.unitCost * qty;
        out.push({
          id: `${t.id}#${n}`,
          saleId: t.id,
          identity,
          acquired: lot.date,
          sold: t.date,
          quantity: qty,
          proceeds,
          cost,
          gain: proceeds - cost,
          longTerm: heldOverAYear(lot.date, t.date),
          year: Number(t.date.slice(0, 4)) || 0,
        });
      });
    }
  }
  return out.sort((a, b) => (a.sold !== b.sold ? (a.sold > b.sold ? -1 : 1) : a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

/** The years with at least one sale, newest first. */
export function salesYears(lines: SaleLine[]): number[] {
  return [...new Set(lines.map((l) => l.year))].sort((a, b) => b - a);
}

export function salesTotals(lines: SaleLine[]): SalesTotals {
  const t: SalesTotals = { proceeds: 0, cost: 0, gain: 0, shortTermGain: 0, longTermGain: 0, quantity: 0, sales: 0 };
  for (const l of lines) {
    t.proceeds += l.proceeds;
    t.cost += l.cost;
    t.gain += l.gain;
    if (l.longTerm) t.longTermGain += l.gain;
    else t.shortTermGain += l.gain;
    t.quantity += l.quantity;
  }
  t.sales = new Set(lines.map((l) => l.saleId)).size;
  return t;
}

/** More than one year: sold after the first anniversary of the purchase. */
export function heldOverAYear(acquired: string, sold: string): boolean {
  const y = Number(acquired.slice(0, 4));
  if (!y) return false;
  return sold > `${y + 1}${acquired.slice(4)}`;
}

/** Whole days between two yyyy-MM-dd dates. */
export function daysHeld(acquired: string, sold: string): number | null {
  const a = Date.parse(`${acquired}T00:00:00Z`);
  const b = Date.parse(`${sold}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  return Math.round((b - a) / 86_400_000);
}

/** Each sale's fees, shipping and tax, by sale id (edits applied). */
export function saleFees(transactions: Transaction[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const t of effectiveTransactions(transactions)) if (t.type === "sale") out.set(t.id, t.fees + t.shipping + t.tax);
  return out;
}

/**
 * A spreadsheet of the lines, laid out like a capital gains form: what, when bought, when sold,
 * what it sold for, what it cost, and the gain.
 */
export function salesCsv(lines: SaleLine[], products: Record<string, Product | undefined>): string {
  const cell = (s: string) => (/[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s);
  const money = (v: number) => v.toFixed(2);
  const rows = ["Description,Set,Condition or grade,Quantity,Date acquired,Date sold,Proceeds,Cost basis,Gain or loss,Term"];
  const sorted = [...lines].sort((a, b) => (a.sold !== b.sold ? (a.sold < b.sold ? -1 : 1) : a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  for (const l of sorted) {
    const p = products[l.identity.productId];
    const grade = l.identity.grade ? `${l.identity.grade.company} ${l.identity.grade.grade}` : l.identity.condition;
    rows.push(
      [cell(p?.name ?? "Unknown item"), cell(p?.setName ?? ""), cell(grade), String(l.quantity), l.acquired ?? "", l.sold, money(l.proceeds), money(l.cost), money(l.gain), l.longTerm ? "Long" : "Short"].join(","),
    );
  }
  return rows.join("\n") + "\n";
}
