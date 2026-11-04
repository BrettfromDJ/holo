import "server-only";
import { matchesNumber, numberPatterns, parseNumberToken } from "../search-match";
import type { ScanCandidate, ScanResult } from "../scan-types";
import { withPrices } from "../server/explore";
import type { SupabaseClient } from "@supabase/supabase-js";
import { getAdminSupabase } from "../supabase/server";
import type { Database } from "../supabase/database.types";
import type { ProductRow } from "../supabase/database.types";
import { ScanFailure } from "./identify";
import type { Stopwatch } from "../server/timing";

/**
 * Card scanning with CardSight AI (`POST https://api.cardsight.ai/v1/identify/card[/segment]`,
 * the photo as multipart field `image`, the key in `X-API-Key`). CardSight names the card (name,
 * set, number, and a slab's grade); we then find that card in Holo's own catalog by name and
 * number, so the result carries our product, its printings and its stored price, the same
 * shape the TCG API scanner returns. Used when `CARDSIGHT_API_KEY` is set on the server.
 */

const BASE = process.env.CARDSIGHT_BASE_URL ?? "https://api.cardsight.ai";
const TIMEOUT_MS = 45_000;

/** Our game names to CardSight segment shortnames; anything else lets CardSight detect it. */
const SEGMENTS: Record<string, string> = { pokemon: "pokemon", "pokemon-japan": "pokemon", magic: "magic", mtg: "magic", "one-piece": "one-piece", onepiece: "one-piece" };

export function cardSightConfigured(): boolean {
  return Boolean(process.env.CARDSIGHT_API_KEY);
}

interface CsCard {
  id?: string;
  name?: string;
  number?: string;
  setName?: string;
  releaseName?: string;
  year?: string | number;
}

interface CsDetection {
  confidence?: "High" | "Medium" | "Low";
  card?: CsCard;
  grading?: { company?: { name?: string }; grade?: { value?: string | number } } | null;
}

interface CsResult {
  success?: boolean;
  detections?: CsDetection[];
  messages?: { type?: string; message?: string }[];
}

/** Catalog products for a name and collector number, best set match first. */
async function findInCatalog(card: CsCard): Promise<ProductRow[]> {
  const admin = getAdminSupabase();
  if (!admin || !card.name) return [];
  const name = card.name.replace(/[%_,()*]/g, " ").trim();
  const head = (card.number ?? "").split("/")[0]?.replace(/^#/, "").trim();
  const n = head ? parseNumberToken(head.toLowerCase()) : null;
  let query = admin.from("products").select("*").eq("source", "tcgapi").ilike("name", `%${name}%`);
  if (n) query = query.or(numberPatterns(n).map((p) => `number.ilike.${p}`).join(","));
  const { data } = await query.limit(60);
  let rows = (data ?? []) as ProductRow[];
  if (n) rows = rows.filter((r) => matchesNumber(r.number, n));
  // Prefer the set CardSight named ("Evolving Skies" in "SWSH07: Evolving Skies").
  const set = (card.setName ?? card.releaseName ?? "").toLowerCase();
  const words = set.split(/[^a-z0-9]+/).filter((w) => w.length > 2);
  const score = (r: ProductRow) => words.filter((w) => (r.set_name ?? "").toLowerCase().includes(w)).length;
  return rows.sort((a, b) => score(b) - score(a)).slice(0, 6);
}

/** Identify the card or slab in one photo with CardSight, then match it in the catalog. */
export async function identifyWithCardSight(image: Blob, opts: { game?: string; clock?: Stopwatch } = {}): Promise<ScanResult> {
  const apiKey = process.env.CARDSIGHT_API_KEY;
  if (!apiKey) throw new ScanFailure("not_configured", "Scanning needs a CardSight key on the server.", 503);
  const segment = opts.game ? SEGMENTS[opts.game.toLowerCase()] : undefined;
  const form = new FormData();
  form.append("image", image, "photo.jpg");

  let res: Response;
  try {
    res = await fetch(`${BASE}/v1/identify/card${segment ? `/${segment}` : ""}`, {
      method: "POST",
      headers: { "X-API-Key": apiKey, Accept: "application/json" },
      body: form,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch {
    throw new ScanFailure("upstream", "Couldn't reach the scanner. Try again.", 502);
  }
  const body = (await res.json().catch(() => null)) as (CsResult & { data?: CsResult; error?: { message?: string } | string; message?: string }) | null;
  opts.clock?.lap("cardsight");
  if (!res.ok) {
    // What CardSight said, for the Vercel log, plus the key's length and whether it has
    // stray spaces or quotes (never the key itself), so a mispasted one can be spotted.
    const hint = `${apiKey.length} chars${/\s/.test(apiKey) ? ", has whitespace" : ""}${/["']/.test(apiKey) ? ", has quotes" : ""}`;
    console.error("cardsight error", res.status, JSON.stringify(body).slice(0, 500), "key:", hint);
    if (res.status === 429) throw new ScanFailure("rate_limited", "Scanning too fast. Give it a second.", 429);
    if (res.status === 402) throw new ScanFailure("scan_balance_empty", "You're out of CardSight scans.", 402);
    if (res.status === 400 || res.status === 413 || res.status === 415) throw new ScanFailure("bad_image", "That photo couldn't be read.", 400);
    if (res.status === 401 || res.status === 403) throw new ScanFailure("upstream", "CardSight rejected the scanner key.", 502);
    throw new ScanFailure("upstream", "The scanner had a problem. Try again.", 502);
  }
  const data: CsResult = body?.data ?? body ?? {};
  console.log("cardsight reply", JSON.stringify({ status: res.status, success: data.success, detections: data.detections?.length ?? null, messages: data.messages ?? null, keys: Object.keys(body ?? {}) }).slice(0, 600));
  const found = (data.detections ?? []).filter((d) => d.card?.name || d.grading);
  if (!found.length) {
    return { status: "retake", message: "No card found in the photo. Fill the frame with the card and try again.", read: null, candidates: [], scansRemaining: null };
  }
  // Every card in the photo, each matched in the catalog; the first leads, the rest ride along.
  const results = await Promise.all(found.slice(0, 12).map(toResult));
  opts.clock?.lap("catalog");
  const [first, ...others] = results;
  return others.length ? { ...first, others } : first;
}

/** One detected card (or slab) as a scan result, matched in our catalog. */
async function toResult(detection: CsDetection): Promise<ScanResult> {
  const g = detection.grading;
  const grade = g?.company?.name && g.grade?.value !== undefined ? { company: g.company.name, grade: String(g.grade.value) } : null;
  const read: ScanResult["read"] = { kind: g ? "slab" : "raw", grade };
  const card = detection.card ?? {};
  if (!card.name) {
    return { status: "not_found", message: "Couldn't tell which card this is. Try again, or search for it.", read, candidates: [], scansRemaining: null };
  }

  const admin = getAdminSupabase();
  if (!admin) return { status: "not_found", message: "Couldn't tell which card this is. Try again, or search for it.", read, candidates: [], scansRemaining: null };
  // Which catalog products this CardSight card is, remembered for 30 days: a card scanned
  // before skips the catalog search. Prices are read fresh below, with the set names, both at
  // once; the memo is saved alongside rather than before.
  const memoKey = `cardsight-map:${card.id ?? [card.name, card.number, card.setName ?? card.releaseName].join("|").toLowerCase()}`;
  const db = admin as unknown as SupabaseClient<Database>;
  const { data: memo } = await db.from("api_cache").select("value, expires_at").eq("key", memoKey).maybeSingle();
  const knownIds = memo && Date.parse(memo.expires_at) > Date.now() ? (memo.value as string[]) : null;
  let rows: ProductRow[] = [];
  let saving: PromiseLike<unknown> = Promise.resolve();
  if (knownIds) {
    if (knownIds.length) {
      const { data } = await admin.from("products").select("*").in("id", knownIds);
      const byId = new Map((data ?? []).map((r) => [r.id, r as ProductRow]));
      rows = knownIds.map((id) => byId.get(id)).filter((r): r is ProductRow => Boolean(r));
    }
  } else {
    rows = await findInCatalog(card);
    if (rows.length) {
      const expires = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();
      // Best effort, started now and finished while the prices load.
      saving = db.from("api_cache").upsert({ key: memoKey, value: rows.map((r) => r.id) as never, expires_at: expires }).then(() => undefined, () => undefined);
    }
  }
  const [priced] = await Promise.all([rows.length ? withPrices(admin, rows) : Promise.resolve([]), saving]);
  const candidates: ScanCandidate[] = priced.map((p, i) => ({
    product: p.product,
    printing: p.printing,
    printings: p.product.printings ?? (p.printing ? [p.printing] : []),
    market: p.market,
    slabMarket: null,
    score: detection.confidence === "High" ? 1 - i * 0.1 : detection.confidence === "Medium" ? 0.7 - i * 0.1 : 0.4 - i * 0.1,
  }));
  if (!candidates.length) {
    const what = [card.name, card.setName ?? card.releaseName, card.number && `#${card.number}`].filter(Boolean).join(" · ");
    return { status: "not_found", message: `CardSight read ${what}, but it isn't in the catalog yet.`, read, candidates: [], scansRemaining: null };
  }
  const sure = candidates.length === 1 || detection.confidence === "High";
  return { status: sure ? "matched" : "ambiguous", message: null, read, candidates, scansRemaining: null };
}
