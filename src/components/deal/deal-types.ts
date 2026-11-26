import type { CSSProperties } from "react";
import type { DealKind } from "@/lib/deal";
import type { Product } from "@/lib/types";
import type { DealItem, DealSide } from "./deal-picker";

/** The deal in progress (user_state "deal", shared with the app). */
export interface DealState {
  in: DealItem[];
  out: DealItem[];
  /** Rates moved off the defaults for this deal; null follows the presets. */
  rateIn: number | null;
  rateOut: number | null;
  /** Photos documenting the deal (storage paths, shared with the app). */
  photos?: string[];
  /** Your own notes on the deal (kept with it when it closes). */
  notes?: string;
  /**
   * Cash the two of you settled on, signed like the balance (positive: they pay you). While set,
   * one side's prices are spread to reach it (see agreedDeal); unset follows the prices. Any
   * renegotiation clears it. Shared with the app.
   */
  agreedCash?: number | null;
}

/** A deal set aside to finish later (user_state "deals-parked", shared with the app). */
export interface ParkedDeal {
  id: string;
  name: string;
  savedAt: string;
  state: DealState;
}

/** A closed deal (user_state "deals", shared with the app). */
export interface DealRecord {
  id: string;
  at: string;
  kind: DealKind;
  inValue: number;
  outValue: number;
  balance: number;
  profit: number | null;
  equity: number;
  /** How far ahead the deal left you (profit + value gained); null when not every item had a cost. Missing on older deals. */
  ahead?: number | null;
  /** Items that went out with no known cost. Recorded alongside `ahead`. */
  uncosted?: number;
  items: number;
  /** What changed hands, for the history. Missing on deals closed before it was kept. */
  lines?: DealRecordLine[];
  photos?: string[];
  notes?: string;
}

export interface DealRecordLine {
  side: DealSide;
  product: Pick<Product, "id" | "name" | "imageUrl" | "kind" | "setName" | "productType">;
  qty: number;
  /** Price per unit it went at. */
  price: number;
  /** Not recorded in the collection (left out on purpose, not in Holo, or custom). */
  untracked?: boolean;
}

export const EMPTY: DealState = { in: [], out: [], rateIn: null, rateOut: null };

/** The kind of deal you picked: buy, sell or trade (the app's "deal-path"). */
export type DealPath = "buy" | "sell" | "trade";

/** "Buying" / "Selling" / "Trading": the kind word on rows and the editor's bar title. */
export const PATH_TITLE: Record<DealKind, string> = { buy: "Buying", sell: "Selling", trade: "Trading", empty: "Deal" };
/** The deal card's tag (the app's DealKind.label). */
export const KIND_LABEL: Record<DealKind, string> = { buy: "Buying", sell: "Selling", trade: "Trade", empty: "New deal" };
/** The deal as a noun: "Close this buy?", "Sale recorded". */
export const KIND_NOUN: Record<DealKind, string> = { buy: "Buy", sell: "Sale", trade: "Trade", empty: "Deal" };

/** Each deal kind's colours (the owner's mockup): blue buy, lime sell, purple trade. Same as the app's DealKind tints. */
export const KIND_COLOR: Record<DealKind, { tint: string; deep: string; onTint: string; button: string; base: string; btn3d: string }> = {
  buy: { tint: "#5B82FF", deep: "#2F5BFF", onTint: "#ffffff", button: "#2F5BFF", base: "#0C1A4A", btn3d: "btn-3d-blue" },
  sell: { tint: "#D4FF3A", deep: "#9FE02A", onTint: "#0b0b0c", button: "#D4FF3A", base: "#2F3A0A", btn3d: "btn-3d-lime" },
  trade: { tint: "#A584FF", deep: "#7B5CF0", onTint: "#ffffff", button: "#7B5CF0", base: "#22124A", btn3d: "btn-3d-purple" },
  empty: { tint: "#D4FF3A", deep: "#9FE02A", onTint: "#0b0b0c", button: "#D4FF3A", base: "#2F3A0A", btn3d: "btn-3d-lime" },
};

/** A solid button in the kind's colour (Add cards, Review deal, Complete deal). */
export function kindButton(kind: DealKind): CSSProperties {
  const c = KIND_COLOR[kind];
  return { backgroundColor: c.button, color: c.onTint };
}

/** What each number means, one line each (tap the ⓘ). Same words as the app's DealTerm. */
export const TERMS = {
  verdict: { title: "Profit or loss", text: "Your profit on what you hand over plus the value you gain on what comes in: how much better off you are after this deal, at market prices." },
  ahead: { title: "Profit or loss", text: "Market value of what comes in, minus what you paid for what goes out, minus any cash you pay (plus any you get): your profit plus the value you gain." },
  cash: { title: "Cash", text: "The difference between the two sides, paid in cash so the deal comes out even." },
  comingIn: { title: "Coming in", text: "What their cards count for in this deal, at the prices you set." },
  goingOut: { title: "Going out", text: "What your cards count for in this deal, at the prices you set." },
  profit: { title: "Sale profit", text: "What your cards go for in this deal, minus what you paid for them." },
  value: { title: "Trade-in value", text: "Market value of what comes in, minus what you're giving for it: how far below market you're getting it." },
  rate: { title: "Share of market", text: "What you pay for the cards, as a share of their market price." },
  market: { title: "Market value", text: "What the cards are worth at today's market prices." },
  paid: { title: "You paid", text: "What you paid for the cards you're selling, from your collection's records (or what you typed in)." },
  gain: { title: "Profit", text: "On a buy: what the cards are worth at market, minus what you pay; what you'd make reselling them at market. On a sale: what you sell for, minus what you paid." },
} as const;
export type DealTerm = keyof typeof TERMS;

/** "3 cards". */
export function cardsLabel(n: number) {
  return `${n} card${n === 1 ? "" : "s"}`;
}

/** A closed deal's name: its first card, and how many more. */
export function recordTitle(r: DealRecord): string {
  const first = r.lines?.[0];
  if (!first) return PATH_TITLE[r.kind];
  const more = (r.lines?.length ?? 1) - 1;
  return first.product.name + (more > 0 ? ` +${more}` : "");
}
