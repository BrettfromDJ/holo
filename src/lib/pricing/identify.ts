import "server-only";
import { inferKind } from "../catalog";
import type { ScanCandidate, ScanError, ScanResult, ScanStatus } from "../scan-types";
import type { Product } from "../types";

/**
 * TCG API card scanning: `POST /v1/identify` with a photo, one scan from the
 * account's prepaid balance per call (separate from the daily request quota).
 * Called directly rather than through the SDK: the installed SDK predates
 * identify. Shapes follow the official SDK's `IdentifyResult` types.
 */

const BASE = process.env.TCGAPI_BASE_URL ?? "https://api.tcgapi.dev/v1";
/** A read can take up to ~45s when the model host is busy. */
const TIMEOUT_MS = 60_000;
export const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

interface RawCandidate {
  card_id: number;
  tcgplayer_id: number | null;
  name: string;
  number: string | null;
  rarity: string | null;
  product_type: string | null;
  set: { id: number; name: string; code: string | null };
  image_url: string | null;
  printings: string[];
  suggested_printing: string | null;
  score: number;
  prices?: { printing: string; market_price: number | null; ebay?: { slab_grade?: { median_30d: number | null; last_price: number | null } | null } | null }[];
}

interface RawResult {
  status: ScanStatus;
  message: string | null;
  read: { kind: "raw" | "slab" | "sealed" | "unknown"; grade: { company: string | null; grade: string | null } | null } | null;
  candidates: RawCandidate[];
}

export class ScanFailure extends Error {
  constructor(
    public readonly code: ScanError["code"],
    message: string,
    public readonly status: number,
  ) {
    super(message);
  }
}

function key() {
  const k = process.env.TCGAPI_KEY;
  if (!k) throw new ScanFailure("not_configured", "Scanning needs a TCG API key on the server.", 503);
  return k;
}

function toCandidate(c: RawCandidate, sealed: boolean): ScanCandidate {
  const printing = c.suggested_printing ?? c.printings[0] ?? null;
  const price = c.prices?.find((p) => p.printing === printing) ?? c.prices?.[0];
  const product: Product = {
    id: `tcgapi:${c.card_id}`,
    source: "tcgapi",
    externalId: String(c.card_id),
    name: c.name,
    setName: c.set?.name ?? null,
    // The catalog import fills the set slug in; the scan only knows the set's code.
    setId: null,
    number: c.number,
    rarity: c.rarity,
    productType: c.product_type,
    kind: inferKind({ productType: c.product_type, number: c.number, name: c.name }, sealed ? "sealed" : undefined),
    imageUrl: c.image_url,
    tcgplayerId: c.tcgplayer_id,
    tcgplayerUrl: null,
    printings: c.printings,
  };
  const slab = price?.ebay?.slab_grade ?? c.prices?.find((p) => p.ebay?.slab_grade)?.ebay?.slab_grade;
  return { product, printing, printings: c.printings, market: price?.market_price ?? null, slabMarket: slab ? (slab.median_30d ?? slab.last_price) : null, score: c.score };
}

/** Identify the card, slab or sealed product in one photo. Uses one scan. */
export async function identifyPhoto(image: Blob, opts: { game?: string } = {}): Promise<ScanResult> {
  const url = new URL(`${BASE}/identify`);
  // "ebay" implies prices, and on a slab adds eBay sold figures for the grade on its label (no extra charge).
  url.searchParams.set("include", "ebay");
  if (opts.game) url.searchParams.set("game", opts.game);
  const form = new FormData();
  form.append("image", image, "photo");

  let res: Response;
  try {
    res = await fetch(url, { method: "POST", headers: { "X-API-Key": key(), Accept: "application/json", "User-Agent": "holo-collection-tracker" }, body: form, signal: AbortSignal.timeout(TIMEOUT_MS) });
  } catch (err) {
    if (err instanceof ScanFailure) throw err;
    throw new ScanFailure("upstream", "Couldn't reach the scanner. Try again.", 502);
  }
  const body = (await res.json().catch(() => null)) as { data?: RawResult; meta?: { scans_remaining?: number }; error?: { code?: string; message?: string } } | null;

  if (!res.ok) {
    const code = body?.error?.code;
    if (res.status === 402 || code === "SCAN_BALANCE_EMPTY") throw new ScanFailure("scan_balance_empty", "You're out of scans. Buy more in your TCG API dashboard.", 402);
    if (res.status === 429) throw new ScanFailure("rate_limited", "Scanning too fast. Give it a second.", 429);
    if (res.status === 400 || res.status === 413 || res.status === 415) throw new ScanFailure("bad_image", body?.error?.message ?? "That photo couldn't be read.", 400);
    if (res.status === 401 || res.status === 403) throw new ScanFailure("upstream", "TCG API rejected the scanner key.", 502);
    throw new ScanFailure("upstream", body?.error?.message ?? "The scanner had a problem. Try again.", 502);
  }
  const data = body?.data;
  if (!data) throw new ScanFailure("upstream", "The scanner sent back nothing.", 502);

  const sealed = data.read?.kind === "sealed";
  const g = data.read?.grade;
  return {
    status: data.status,
    message: data.message ?? null,
    read: data.read ? { kind: data.read.kind, grade: g?.company && g.grade ? { company: g.company, grade: g.grade } : null } : null,
    candidates: (data.candidates ?? []).slice(0, 6).map((c) => toCandidate(c, sealed)),
    scansRemaining: body?.meta?.scans_remaining ?? null,
  };
}

/** Scan balance (free: no scan, no daily quota). */
export async function scanBalance(): Promise<number | null> {
  const res = await fetch(`${BASE}/identify/usage`, { headers: { "X-API-Key": key(), Accept: "application/json" }, signal: AbortSignal.timeout(15_000) });
  if (!res.ok) return null;
  const body = (await res.json().catch(() => null)) as { data?: { balance?: number } } | null;
  return body?.data?.balance ?? null;
}
