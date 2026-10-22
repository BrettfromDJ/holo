import type { Product } from "../types";
import type { RealizedEntry } from "./ledger";
import type { HoldingCategory, HoldingView } from "./portfolio";

/**
 * Gain attribution: break a gain total down into the products (or sets, or
 * categories) it comes from, as steps of a waterfall that sum exactly to the
 * total. Unrealized gains come from current holdings with a market price;
 * realized gains come from completed sales and write-offs.
 */

export type GainMode = "unrealized" | "realized" | "all";
export type GainGroup = "product" | "set" | "category";

export interface GainRow {
  key: string;
  label: string;
  /** Representative product, for imagery (product grouping only). */
  product: Product | undefined;
  category: HoldingCategory | null;
  gain: number;
  unrealized: number;
  realized: number;
  /** Market value of what's still held (priced only). */
  value: number;
  /** Cost basis of what's still held (priced only). */
  costBasis: number;
  /** Units still held. */
  quantity: number;
  /** Rows folded into an "Other" bucket. */
  members?: number;
}

export interface WaterfallStep extends GainRow {
  start: number;
  end: number;
}

export interface GainAttribution {
  steps: WaterfallStep[];
  total: number;
  /** Sum of positive contributions. */
  gains: number;
  /** Sum of negative contributions (≤ 0). */
  losses: number;
  winners: number;
  losers: number;
  /** Share of positive gains coming from the top three contributors. */
  topThreeShare: number | null;
  /** Holdings left out because they have no market price. */
  unpriced: number;
}

export const CATEGORY_LABEL: Record<HoldingCategory, string> = { sealed: "Sealed", single: "Singles", graded: "Graded" };

function realizedCategory(entry: RealizedEntry, product: Product | undefined): HoldingCategory {
  const grade = entry.holdingKey.split("|")[3];
  if (grade) return "graded";
  return product?.kind === "sealed" ? "sealed" : "single";
}

export function attributeGains(
  holdings: HoldingView[],
  realized: RealizedEntry[],
  products: Record<string, Product>,
  opts: { mode: GainMode; group: GainGroup; maxRows?: number },
): GainAttribution {
  const rows = new Map<string, GainRow>();
  const groupOf = (productId: string, category: HoldingCategory): { key: string; label: string } => {
    const product = products[productId];
    if (opts.group === "product") return { key: productId, label: product?.name ?? "Unknown product" };
    if (opts.group === "set") return { key: product?.setName ?? "—", label: product?.setName ?? "Unknown set" };
    return { key: category, label: CATEGORY_LABEL[category] };
  };
  const rowFor = (productId: string, category: HoldingCategory) => {
    const { key, label } = groupOf(productId, category);
    let row = rows.get(key);
    if (!row) {
      row = {
        key,
        label,
        product: opts.group === "category" ? undefined : products[productId],
        category: opts.group === "product" ? category : opts.group === "category" ? category : null,
        gain: 0,
        unrealized: 0,
        realized: 0,
        value: 0,
        costBasis: 0,
        quantity: 0,
      };
      rows.set(key, row);
    }
    return row;
  };

  let unpriced = 0;
  if (opts.mode !== "realized") {
    for (const h of holdings) {
      if (h.unrealized === null || h.value === null) {
        unpriced++;
        continue;
      }
      const row = rowFor(h.identity.productId, h.category);
      row.unrealized += h.unrealized;
      row.value += h.value;
      row.costBasis += h.costBasis;
      row.quantity += h.quantity;
    }
  }
  if (opts.mode !== "unrealized") {
    for (const e of realized) {
      const productId = e.holdingKey.split("|")[0];
      const row = rowFor(productId, realizedCategory(e, products[productId]));
      row.realized += e.gain;
    }
  }

  const all = [...rows.values()]
    .map((r) => ({ ...r, gain: r.unrealized + r.realized }))
    .filter((r) => Math.abs(r.gain) >= 0.005);

  // Keep the biggest movers; fold the long tail into a single "Other" step.
  const maxRows = opts.maxRows ?? Infinity;
  let shown = all;
  let other: GainRow | null = null;
  if (all.length > maxRows) {
    // Always keep the biggest losers visible so losses aren't hidden in "Other".
    const keepLosers = all.filter((r) => r.gain < 0).sort((a, b) => a.gain - b.gain).slice(0, Math.min(3, maxRows - 1));
    const byImpact = all.filter((r) => !keepLosers.includes(r)).sort((a, b) => Math.abs(b.gain) - Math.abs(a.gain));
    const slots = maxRows - 1 - keepLosers.length;
    shown = [...byImpact.slice(0, slots), ...keepLosers];
    const rest = byImpact.slice(slots);
    other = rest.reduce<GainRow>(
      (acc, r) => ({
        ...acc,
        gain: acc.gain + r.gain,
        unrealized: acc.unrealized + r.unrealized,
        realized: acc.realized + r.realized,
        value: acc.value + r.value,
        costBasis: acc.costBasis + r.costBasis,
        quantity: acc.quantity + r.quantity,
      }),
      { key: "__other", label: `${rest.length} others`, product: undefined, category: null, gain: 0, unrealized: 0, realized: 0, value: 0, costBasis: 0, quantity: 0, members: rest.length },
    );
  }

  // Waterfall order: gains (largest first) climb, then losses (largest first) fall.
  const ordered = [...shown.filter((r) => r.gain > 0).sort((a, b) => b.gain - a.gain), ...shown.filter((r) => r.gain < 0).sort((a, b) => a.gain - b.gain)];
  if (other && Math.abs(other.gain) >= 0.005) ordered.push(other);

  let running = 0;
  const steps = ordered.map((r) => {
    const start = running;
    running += r.gain;
    return { ...r, start, end: running };
  });

  const positives = all.filter((r) => r.gain > 0).sort((a, b) => b.gain - a.gain);
  const gains = positives.reduce((s, r) => s + r.gain, 0);
  const losses = all.filter((r) => r.gain < 0).reduce((s, r) => s + r.gain, 0);
  return {
    steps,
    total: gains + losses,
    gains,
    losses,
    winners: positives.length,
    losers: all.length - positives.length,
    topThreeShare: gains > 0 ? positives.slice(0, 3).reduce((s, r) => s + r.gain, 0) / gains : null,
    unpriced,
  };
}
