import { holdingKey, type HoldingIdentity, type ISODate, type Transaction } from "../types";

/**
 * The ledger turns an append-only transaction log into FIFO lots.
 *
 * Transactions are never edited in place. A `correction` row points at the
 * transaction it fixes (`correctsId`) and supplies replacement economics; a
 * correction with quantity 0 voids the original. This keeps a complete audit
 * trail while the engine works with the "effective" view.
 */

export interface Lot {
  transactionId: string;
  date: ISODate;
  /** Units remaining in the lot. */
  quantity: number;
  /** Fully loaded cost per unit (price + allocated fees, shipping and tax). */
  unitCost: number;
}

export interface RealizedEntry {
  transactionId: string;
  holdingKey: string;
  date: ISODate;
  kind: "sale" | "adjustment";
  quantity: number;
  proceeds: number;
  costBasis: number;
  gain: number;
}

export interface LedgerWarning {
  transactionId: string;
  message: string;
}

export interface PositionState {
  identity: HoldingIdentity;
  lots: Lot[];
  realized: RealizedEntry[];
  /** Sum of loaded purchase costs ever (for "total invested" style metrics). */
  totalPurchased: number;
  firstAcquired: ISODate | null;
  lastAcquired: ISODate | null;
}

/** A cash or in-kind flow into or out of the portfolio on a specific day. */
export interface Flow {
  holdingKey: string;
  date: ISODate;
  /** Positive = units entered the portfolio, negative = units left. */
  units: number;
  /** Cash paid (purchases) or received (sales). Positive = paid in. */
  cash: number;
}

const EPS = 1e-9;

/** Loaded cost of a purchase (or positive adjustment) including all extras. */
export function acquisitionCost(t: Pick<Transaction, "quantity" | "unitPrice" | "fees" | "shipping" | "tax">): number {
  return Math.abs(t.quantity) * t.unitPrice + t.fees + t.shipping + t.tax;
}

/** Net proceeds of a sale after selling fees, shipping and tax. */
export function saleProceeds(t: Pick<Transaction, "quantity" | "unitPrice" | "fees" | "shipping" | "tax">): number {
  return t.quantity * t.unitPrice - t.fees - t.shipping - t.tax;
}

function compareTx(a: Transaction, b: Transaction): number {
  if (a.date !== b.date) return a.date < b.date ? -1 : 1;
  // Same day: acquisitions before disposals so same-day buy/sell works.
  const rank = (t: Transaction) => (t.type === "purchase" || (t.type === "adjustment" && t.quantity > 0) ? 0 : 1);
  const r = rank(a) - rank(b);
  if (r !== 0) return r;
  return a.createdAt < b.createdAt ? -1 : a.createdAt > b.createdAt ? 1 : 0;
}

/**
 * Resolve corrections into the effective transaction list, sorted for replay.
 * The latest correction (by createdAt) for a given original wins.
 */
export function effectiveTransactions(all: Transaction[]): Transaction[] {
  const byId = new Map(all.map((t) => [t.id, t]));
  const rootOf = (id: string): string => {
    let cur = byId.get(id);
    const seen = new Set<string>();
    while (cur && cur.type === "correction" && cur.correctsId && !seen.has(cur.id)) {
      seen.add(cur.id);
      const next = byId.get(cur.correctsId);
      if (!next) break;
      cur = next;
    }
    return cur?.id ?? id;
  };

  const latestCorrection = new Map<string, Transaction>();
  for (const t of all) {
    if (t.type !== "correction" || !t.correctsId) continue;
    const root = rootOf(t.correctsId);
    const prev = latestCorrection.get(root);
    if (!prev || prev.createdAt <= t.createdAt) latestCorrection.set(root, t);
  }

  const out: Transaction[] = [];
  for (const t of all) {
    if (t.type === "correction") continue;
    const c = latestCorrection.get(t.id);
    if (!c) {
      out.push(t);
      continue;
    }
    if (c.quantity === 0) continue; // voided
    out.push({
      ...t,
      date: c.date,
      quantity: t.type === "adjustment" ? c.quantity : Math.abs(c.quantity),
      unitPrice: c.unitPrice,
      fees: c.fees,
      shipping: c.shipping,
      tax: c.tax,
      notes: c.notes ?? t.notes,
      source: c.source ?? t.source,
    });
  }
  return out.sort(compareTx);
}

/**
 * Stateful FIFO ledger. Apply effective transactions in order; read positions
 * at any point. Used both for "as of today" holdings and for day-by-day
 * timeline replay.
 */
export class Ledger {
  readonly positions = new Map<string, PositionState>();
  readonly warnings: LedgerWarning[] = [];

  private position(identity: HoldingIdentity): PositionState {
    const key = holdingKey(identity);
    let p = this.positions.get(key);
    if (!p) {
      p = {
        identity: {
          productId: identity.productId,
          printing: identity.printing,
          condition: identity.condition,
          grade: identity.grade,
        },
        lots: [],
        realized: [],
        totalPurchased: 0,
        firstAcquired: null,
        lastAcquired: null,
      };
      this.positions.set(key, p);
    }
    return p;
  }

  /** Apply one effective transaction. Returns the resulting flow. */
  apply(t: Transaction): Flow | null {
    const key = holdingKey(t);
    const p = this.position(t);

    const acquire = (qty: number, cost: number) => {
      p.lots.push({ transactionId: t.id, date: t.date, quantity: qty, unitCost: qty > 0 ? cost / qty : 0 });
      if (!p.firstAcquired || t.date < p.firstAcquired) p.firstAcquired = t.date;
      if (!p.lastAcquired || t.date > p.lastAcquired) p.lastAcquired = t.date;
    };

    const consume = (qty: number): { taken: number; cost: number } => {
      let remaining = qty;
      let cost = 0;
      for (const lot of p.lots) {
        if (remaining <= EPS) break;
        const take = Math.min(lot.quantity, remaining);
        lot.quantity -= take;
        remaining -= take;
        cost += take * lot.unitCost;
      }
      p.lots = p.lots.filter((l) => l.quantity > EPS);
      if (remaining > EPS) {
        this.warnings.push({
          transactionId: t.id,
          message: `Disposed of ${qty} units but only ${qty - remaining} were held; the excess was ignored.`,
        });
      }
      return { taken: qty - remaining, cost };
    };

    switch (t.type) {
      case "purchase": {
        if (t.quantity <= 0) return null;
        const cost = acquisitionCost(t);
        acquire(t.quantity, cost);
        p.totalPurchased += cost;
        return { holdingKey: key, date: t.date, units: t.quantity, cash: cost };
      }
      case "sale": {
        if (t.quantity <= 0) return null;
        const { taken, cost } = consume(t.quantity);
        if (taken <= EPS) return null;
        // Pro-rate proceeds if the sale was clamped.
        const proceeds = saleProceeds(t) * (taken / t.quantity);
        p.realized.push({
          transactionId: t.id,
          holdingKey: key,
          date: t.date,
          kind: "sale",
          quantity: taken,
          proceeds,
          costBasis: cost,
          gain: proceeds - cost,
        });
        return { holdingKey: key, date: t.date, units: -taken, cash: -proceeds };
      }
      case "adjustment": {
        if (t.quantity > 0) {
          const cost = acquisitionCost(t);
          acquire(t.quantity, cost);
          p.totalPurchased += cost;
          return { holdingKey: key, date: t.date, units: t.quantity, cash: cost };
        }
        if (t.quantity < 0) {
          const { taken, cost } = consume(-t.quantity);
          if (taken <= EPS) return null;
          p.realized.push({
            transactionId: t.id,
            holdingKey: key,
            date: t.date,
            kind: "adjustment",
            quantity: taken,
            proceeds: 0,
            costBasis: cost,
            gain: -cost,
          });
          return { holdingKey: key, date: t.date, units: -taken, cash: 0 };
        }
        return null;
      }
      case "correction":
        // Corrections are resolved by `effectiveTransactions` before replay.
        return null;
    }
  }
}

export function quantityOf(p: PositionState): number {
  return p.lots.reduce((s, l) => s + l.quantity, 0);
}

export function costBasisOf(p: PositionState): number {
  return p.lots.reduce((s, l) => s + l.quantity * l.unitCost, 0);
}

export function realizedOf(p: PositionState): number {
  return p.realized.reduce((s, r) => s + r.gain, 0);
}

/** Replay a full transaction log and return the final ledger. */
export function buildLedger(transactions: Transaction[], asOf?: ISODate): Ledger {
  const ledger = new Ledger();
  for (const t of effectiveTransactions(transactions)) {
    if (asOf && t.date > asOf) break;
    ledger.apply(t);
  }
  return ledger;
}
