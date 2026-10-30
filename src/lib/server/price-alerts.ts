import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../supabase/database.types";
import { priceKey, type NormalizedPrice } from "../types";
import { isApnsConfigured, sendPush } from "./apns";

/**
 * Price alerts: after the daily price sync, tell each user (on their phones)
 * when a watched card is at or below their target price. One alert per drop:
 * `alerted_at` is set when it fires and cleared once the price climbs back above.
 */
export async function sendPriceAlerts(admin: SupabaseClient<Database>, prices: NormalizedPrice[]) {
  const summary = { checked: 0, alerts: 0, sent: 0, droppedTokens: 0, cleared: 0, skipped: null as string | null };
  if (!isApnsConfigured()) {
    summary.skipped = "APNs is not configured";
    return summary;
  }

  const { data: watches, error } = await admin.from("watchlist_items").select("id, user_id, product_id, printing, target_price, alerted_at").not("target_price", "is", null);
  if (error) {
    summary.skipped = /alerted_at/.test(error.message) ? "Run supabase/migrations/20261031000000_push_notifications.sql" : error.message;
    return summary;
  }

  // Today's price for a watch: its printing, else the product's first priced printing.
  const byKey = new Map(prices.map((p) => [priceKey(p.productId, p.printing), p.market]));
  const firstByProduct = new Map<string, number>();
  for (const p of prices) if (p.market !== null && !firstByProduct.has(p.productId)) firstByProduct.set(p.productId, p.market);
  const marketOf = (w: { product_id: string; printing: string | null }) => byKey.get(priceKey(w.product_id, w.printing)) ?? firstByProduct.get(w.product_id) ?? null;

  const due: { id: string; user_id: string; product_id: string; market: number; target: number }[] = [];
  const recovered: string[] = [];
  for (const w of watches ?? []) {
    const market = marketOf(w);
    if (market === null || w.target_price === null) continue;
    summary.checked++;
    if (market <= w.target_price && !w.alerted_at) due.push({ id: w.id, user_id: w.user_id, product_id: w.product_id, market, target: w.target_price });
    else if (market > w.target_price && w.alerted_at) recovered.push(w.id);
  }
  if (recovered.length) {
    await admin.from("watchlist_items").update({ alerted_at: null }).in("id", recovered);
    summary.cleared = recovered.length;
  }
  if (!due.length) return summary;

  const [{ data: products }, { data: devices }] = await Promise.all([
    admin.from("products").select("id, name, set_name").in("id", [...new Set(due.map((d) => d.product_id))]),
    admin.from("device_tokens").select("token, user_id, environment").in("user_id", [...new Set(due.map((d) => d.user_id))]),
  ]);
  const names = new Map((products ?? []).map((p) => [p.id, p.set_name ? `${p.name} (${p.set_name})` : p.name]));
  const money = (n: number) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(n);

  const fired: string[] = [];
  const dead: string[] = [];
  for (const d of due) {
    const mine = (devices ?? []).filter((x) => x.user_id === d.user_id);
    if (!mine.length) continue; // No phone yet: alert once they have one.
    summary.alerts++;
    const message = {
      title: "Price target hit",
      body: `${names.get(d.product_id) ?? "A card you watch"} is ${money(d.market)}, at or below your ${money(d.target)} target.`,
      data: { productId: d.product_id },
    };
    for (const env of ["production", "sandbox"] as const) {
      const results = await sendPush(mine.filter((x) => x.environment === env).map((x) => x.token), message, env);
      for (const r of results) {
        if (r.ok) summary.sent++;
        else if (r.status === 410 || r.reason === "BadDeviceToken" || r.reason === "Unregistered") dead.push(r.token);
      }
    }
    fired.push(d.id);
  }
  if (fired.length) await admin.from("watchlist_items").update({ alerted_at: new Date().toISOString() }).in("id", fired);
  if (dead.length) {
    await admin.from("device_tokens").delete().in("token", dead);
    summary.droppedTokens = dead.length;
  }
  return summary;
}
