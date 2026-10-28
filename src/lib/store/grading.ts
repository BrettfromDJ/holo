"use client";

import { useCallback } from "react";
import { DEFAULT_GRADING_COSTS, type GradingCosts } from "../graded";
import type { HoldingView } from "../finance/portfolio";
import { holdingKey, type Condition, type Grade, type HoldingIdentity, type ISODate } from "../types";
import { useStore } from "./collection-store";
import { usePortfolios } from "./portfolios";
import { useSyncedState } from "./synced-state";

/** Certification numbers for slabs, keyed by `holdingKey`. */
export function useSlabCerts() {
  const [certs, setCerts] = useSyncedState<Record<string, string>>("slab-certs", {});
  const setCert = useCallback(
    (key: string, cert: string) =>
      setCerts((prev) => {
        const next = { ...prev };
        if (cert.trim()) next[key] = cert.trim();
        else delete next[key];
        return next;
      }),
    [setCerts],
  );
  return { certs, setCert };
}

/** The grading fee and shipping assumed when weighing whether to grade. */
export function useGradingCosts() {
  const [costs, setCosts] = useSyncedState<GradingCosts>("grading-costs", DEFAULT_GRADING_COSTS);
  return { costs, setCosts };
}

export interface GradingSubmission {
  id: string;
  productId: string;
  printing: string | null;
  condition: Condition;
  company: string;
  /** Service level, e.g. "Value", "Regular", "Express". */
  service: string;
  quantity: number;
  /** Grading fee per card. */
  fee: number;
  /** Shipping and insurance per card. */
  shipping: number;
  sentOn: ISODate;
  status: "sent" | "returned";
  grade?: string;
  returnedOn?: ISODate;
}

/**
 * Cards sent off for grading. While a card is at the grader it stays in the
 * collection as a raw card. When it comes back, the raw units are moved into
 * a graded holding: recorded as a sale at their cost (no gain or loss) and a
 * purchase of the slab at that same cost plus the grading fee and shipping.
 */
export function useGradingSubmissions() {
  const [submissions, setSubmissions, ready] = useSyncedState<GradingSubmission[]>("grading-submissions", []);
  const { addTransaction, today } = useStore();
  const { portfolioOf, move } = usePortfolios();

  const send = useCallback(
    (s: Omit<GradingSubmission, "id" | "status">) => setSubmissions((prev) => [...prev, { ...s, id: crypto.randomUUID(), status: "sent" }]),
    [setSubmissions],
  );

  const cancel = useCallback((id: string) => setSubmissions((prev) => prev.filter((s) => s.id !== id)), [setSubmissions]);

  const complete = useCallback(
    async (sub: GradingSubmission, grade: Grade, holding: HoldingView | undefined, returnedOn: ISODate = today) => {
      const raw: HoldingIdentity = { productId: sub.productId, printing: sub.printing, condition: sub.condition, grade: null };
      const slab: HoldingIdentity = { productId: sub.productId, printing: sub.printing, condition: "Near Mint", grade };
      const qty = Math.min(sub.quantity, holding?.quantity ?? sub.quantity);
      // Cost of the units leaving the raw holding, oldest lots first (as the ledger takes them).
      let left = qty;
      let cost = 0;
      for (const lot of holding?.lots ?? []) {
        if (left <= 0) break;
        const take = Math.min(lot.quantity, left);
        cost += take * lot.unitCost;
        left -= take;
      }
      const unit = qty > 0 ? cost / qty : 0;
      const note = `Graded by ${grade.company}: ${grade.company} ${grade.grade}`;
      if (holding && qty > 0) {
        await addTransaction({ ...raw, type: "sale", date: returnedOn, quantity: qty, unitPrice: unit, fees: 0, shipping: 0, tax: 0, source: "Grading", notes: `${note} — moved to a slab` });
      }
      await addTransaction({
        ...slab,
        type: "purchase",
        date: returnedOn,
        quantity: qty,
        unitPrice: unit,
        fees: sub.fee * qty,
        shipping: sub.shipping * qty,
        tax: 0,
        source: "Grading",
        notes: note,
      });
      // Keep the slab in the same portfolio as the raw card it came from.
      const from = portfolioOf(holdingKey(raw));
      if (from !== portfolioOf(holdingKey(slab))) await move(holdingKey(slab), from);
      setSubmissions((prev) => prev.map((s) => (s.id === sub.id ? { ...s, status: "returned", grade: grade.grade, returnedOn } : s)));
    },
    [addTransaction, portfolioOf, move, setSubmissions, today],
  );

  return { submissions, ready, send, cancel, complete };
}
