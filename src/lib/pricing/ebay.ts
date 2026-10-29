import "server-only";
import type { EbaySale, EbaySales, EbayStats } from "../ebay-types";
import { cached } from "./cache";
import { PricingUnavailableError } from "./types";

/**
 * Recent eBay sold listings for a card, from TCG API. Pro plan and up; each
 * call costs 2 request credits, so results are cached for 12 hours here and
 * at the CDN (see the route), and only fetched when someone looks.
 */

const BASE = process.env.TCGAPI_BASE_URL ?? "https://api.tcgapi.dev/v1";
const TTL = 12 * 60 * 60 * 1000;

interface RawStats {
  median_30d: number | null;
  sales_30d: number;
  last_price: number | null;
  last_sold: string | null;
}
interface RawSummary extends RawStats {
  days?: number;
  graded: Record<string, RawStats>;
  as_of: string;
  sales?: { sold_date: string; price: number; best_offer: boolean; list_price: number | null; grade: string | null; condition: string | null; title: string; url: string }[];
}

const stats = (s: RawStats): EbayStats => ({ median: s.median_30d, count: s.sales_30d, lastPrice: s.last_price, lastSold: s.last_sold });

export async function ebaySales(externalId: string, printing: string | null): Promise<EbaySales | null> {
  const key = process.env.TCGAPI_KEY;
  if (!key) throw new PricingUnavailableError("TCG API key is not configured.", "not_configured");
  return cached(`ebay:${externalId}:${printing ?? ""}`, TTL, async () => {
    const url = new URL(`${BASE}/cards/${encodeURIComponent(externalId)}/prices`);
    url.searchParams.set("include", "ebay_sales");
    if (printing) url.searchParams.set("printing", printing);
    const res = await fetch(url, { headers: { "X-API-Key": key, Accept: "application/json", "User-Agent": "holo-collection-tracker" }, signal: AbortSignal.timeout(15_000) });
    if (res.status === 403) throw new PricingUnavailableError("eBay sales need TCG API's Pro plan.", "tier");
    if (res.status === 404) return null;
    if (res.status === 429) throw new PricingUnavailableError("TCG API's daily limit has been reached.", "rate_limited", Number(res.headers.get("retry-after")) || undefined);
    if (!res.ok) throw new PricingUnavailableError("Couldn't load eBay sales.", "upstream");
    const body = (await res.json()) as { data?: { printing: string | null; ebay?: RawSummary | null }[] };
    const rows = body.data ?? [];
    const row = rows.find((r) => (r.printing ?? null) === printing && r.ebay) ?? rows.find((r) => r.ebay);
    const e = row?.ebay;
    if (!e) return null;
    const sales: EbaySale[] = (e.sales ?? []).map((s) => ({ soldDate: s.sold_date, price: s.price, bestOffer: s.best_offer, listPrice: s.list_price, grade: s.grade, condition: s.condition, title: s.title, url: s.url }));
    return {
      printing: row?.printing ?? null,
      ungraded: stats(e),
      graded: Object.fromEntries(Object.entries(e.graded ?? {}).map(([k, v]) => [k, stats(v)])),
      sales,
      asOf: e.as_of,
      days: e.days ?? null,
    };
  });
}
