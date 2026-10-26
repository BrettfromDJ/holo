import { acquisitionCost, effectiveTransactions } from "./finance/ledger";
import type { ISODate, Transaction } from "./types";

export interface BudgetStatus {
  month: string;
  spent: number;
  purchases: number;
  budget: number | null;
  remaining: number | null;
  /** Share of the budget used (can exceed 1). */
  used: number | null;
  /** Spending pace: where the month ends if buying continues at this rate. */
  projected: number;
}

/** What was spent on purchases (incl. fees, shipping, tax) in the month containing `today`. */
export function budgetStatus(transactions: Transaction[], today: ISODate, budget: number | null | undefined): BudgetStatus {
  const month = today.slice(0, 7);
  const buys = effectiveTransactions(transactions).filter((t) => t.type === "purchase" && t.date.startsWith(month) && t.date <= today);
  const spent = buys.reduce((s, t) => s + acquisitionCost(t), 0);
  const [y, m, d] = today.split("-").map(Number);
  const daysInMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const b = budget ?? null;
  return {
    month,
    spent,
    purchases: buys.length,
    budget: b,
    remaining: b === null ? null : b - spent,
    used: b ? spent / b : null,
    projected: (spent / d) * daysInMonth,
  };
}
