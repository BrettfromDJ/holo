import type { Grade, Product } from "./types";

/**
 * Card scanning (TCG API identify) as the app sees it. The server maps TCG
 * API's response into these shapes; the browser never sees the API key.
 */

export type ScanStatus = "matched" | "ambiguous" | "retake" | "not_found" | "unsupported";

export interface ScanCandidate {
  product: Product;
  /** The printing the photo points to (finish, 1st Edition), else the first known one. */
  printing: string | null;
  printings: string[];
  /** Market price for that printing, when TCG API returned prices (top candidate only). */
  market: number | null;
  /** On a slab: the eBay sold median (or last sale) for the grade on its label. */
  slabMarket: number | null;
  score: number;
}

export interface ScanResult {
  status: ScanStatus;
  /** Why a photo needs retaking, or other notes from the reader. */
  message: string | null;
  /** What the photo showed: a raw card, a slab (with its grade when legible) or sealed. */
  read: { kind: "raw" | "slab" | "sealed" | "unknown"; grade: Grade | null } | null;
  candidates: ScanCandidate[];
  /** Scans left on the account after this one, when reported. */
  scansRemaining: number | null;
}

export interface ScanError {
  code: "scan_balance_empty" | "not_configured" | "unauthorized" | "rate_limited" | "bad_image" | "upstream";
  message: string;
}

/** What a scanned item is worth: a slab at its grade's eBay price when known, else the card's market price. */
export function scanValue(c: ScanCandidate, read: ScanResult["read"]): number | null {
  return read?.kind === "slab" && c.slabMarket != null ? c.slabMarket : c.market;
}
