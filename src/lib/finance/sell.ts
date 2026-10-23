import type { Lot } from "./ledger";

/**
 * "What if I sell?" estimates. Platform fees are editable presets, not a
 * live feed — marketplaces change them, so the UI labels them as estimates
 * and lets the user adjust both numbers.
 */

export type SellPlatform = "ebay" | "tcgplayer" | "local" | "custom";

export interface FeeModel {
  /** Percentage of the order total (item price + shipping charged to the buyer). */
  percent: number;
  /** Fixed fee per order. */
  fixed: number;
}

export const PLATFORMS: { id: SellPlatform; label: string; fees: FeeModel; note: string }[] = [
  { id: "ebay", label: "eBay", fees: { percent: 13.25, fixed: 0.4 }, note: "Trading cards final value fee + per-order fee (estimate)" },
  { id: "tcgplayer", label: "TCGplayer", fees: { percent: 13.25, fixed: 0.3 }, note: "Marketplace commission + payment processing (estimate)" },
  { id: "local", label: "In person", fees: { percent: 0, fixed: 0 }, note: "No platform fees" },
  { id: "custom", label: "Custom", fees: { percent: 0, fixed: 0 }, note: "Enter your own fees" },
];

export interface SellInput {
  quantity: number;
  unitPrice: number;
  fees: FeeModel;
  /** Shipping you charge the buyer (fees apply to it on most marketplaces). */
  shippingCharged: number;
  /** What you pay to ship, including supplies. */
  shippingCost: number;
}

export interface SellEstimate {
  gross: number;
  platformFees: number;
  /** What you keep after fees and shipping. */
  net: number;
  /** FIFO cost basis of the units sold. */
  costBasis: number;
  profit: number;
  profitPct: number | null;
  /** Per-unit sale price at which profit is exactly zero. */
  breakEvenUnitPrice: number | null;
  /** Units actually available to sell (clamped to holdings). */
  quantity: number;
}

/** Cost of the first `qty` units under FIFO. */
export function fifoCost(lots: Pick<Lot, "quantity" | "unitCost">[], qty: number): number {
  let remaining = qty;
  let cost = 0;
  for (const lot of lots) {
    if (remaining <= 0) break;
    const take = Math.min(lot.quantity, remaining);
    cost += take * lot.unitCost;
    remaining -= take;
  }
  return cost;
}

export function estimateSale(lots: Pick<Lot, "quantity" | "unitCost">[], input: SellInput): SellEstimate {
  const held = lots.reduce((s, l) => s + l.quantity, 0);
  const quantity = Math.max(0, Math.min(input.quantity, held));
  const rate = Math.max(0, input.fees.percent) / 100;
  const gross = quantity * input.unitPrice;
  const platformFees = quantity > 0 ? (gross + input.shippingCharged) * rate + input.fees.fixed : 0;
  const net = gross + input.shippingCharged - platformFees - input.shippingCost;
  const costBasis = fifoCost(lots, quantity);
  const profit = net - costBasis;

  // Solve q·p·(1−r) + S·(1−r) − fixed − shippingCost = basis for p.
  const breakEvenUnitPrice =
    quantity > 0 && rate < 1 ? (costBasis + input.fees.fixed + input.shippingCost - input.shippingCharged * (1 - rate)) / (quantity * (1 - rate)) : null;

  return {
    gross,
    platformFees,
    net,
    costBasis,
    profit,
    profitPct: costBasis > 0 ? profit / costBasis : null,
    breakEvenUnitPrice: breakEvenUnitPrice === null ? null : Math.max(0, breakEvenUnitPrice),
    quantity,
  };
}
