import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../supabase/database.types";
import type { CollectionData, ISODate } from "../types";
import { computeHoldings, summarize, totalRealized, type HoldingView } from "../finance/portfolio";
import { pickNew, reachedMilestones } from "../milestones";
import { isApnsConfigured, sendPush, type PushMessage } from "./apns";
import { readNotificationPrefs } from "../notification-prefs";

type Admin = SupabaseClient<Database>;
type Device = { token: string; environment: "sandbox" | "production" };

const money = (n: number) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(n);
const shortName = (name: string) => name.replace(/\s*\(.*?\)\s*/g, " ").trim();

/** A card's move today worth a notification: at least 15% and $25 either way. */
export const MOVE_MIN_PCT = 0.15;
export const MOVE_MIN_DOLLARS = 25;

/** The biggest move today among your copies, if one is big enough to tell you about. */
export function bigMove(holdings: HoldingView[]): PushMessage | null {
  const moving = holdings
    .filter((h) => h.product && h.dayChange !== null && h.dayChangePct !== null)
    .filter((h) => Math.abs(h.dayChangePct!) >= MOVE_MIN_PCT && Math.abs(h.dayChange!) >= MOVE_MIN_DOLLARS)
    .sort((a, b) => Math.abs(b.dayChange!) - Math.abs(a.dayChange!));
  const h = moving[0];
  if (!h) return null;
  const up = h.dayChange! > 0;
  const pct = Math.round(Math.abs(h.dayChangePct!) * 100);
  return {
    title: `${shortName(h.product!.name)} is ${up ? "up" : "down"} ${pct}% today`,
    body: `Yours is now worth ${money(h.value ?? 0)}, ${up ? "+" : "−"}${money(Math.abs(h.dayChange!))} since yesterday.`,
    data: { productId: h.identity.productId },
  };
}

/**
 * The set you're closest to finishing (1 to 5 singles missing), from the stored catalog: every
 * single in the set against the singles you own from it.
 */
export async function nearlyFinishedSet(admin: Admin, holdings: HoldingView[]): Promise<PushMessage | null> {
  const owned = new Map<string, { name: string; ids: Set<string> }>();
  for (const h of holdings) {
    const p = h.product;
    if (!p || p.kind !== "single" || !p.setId || p.source === "sample") continue;
    const set = owned.get(p.setId) ?? { name: p.setName ?? p.setId, ids: new Set<string>() };
    set.ids.add(p.id);
    owned.set(p.setId, set);
  }
  let best: { setId: string; name: string; missing: number } | null = null;
  for (const [setId, set] of owned) {
    if (set.ids.size < 5) continue; // Only sets you're actually collecting.
    const { count } = await admin.from("products").select("id", { count: "exact", head: true }).eq("set_id", setId).eq("kind", "single");
    if (!count) continue;
    const missing = count - set.ids.size;
    if (missing >= 1 && missing <= 5 && (!best || missing < best.missing)) best = { setId, name: set.name, missing };
  }
  if (!best) return null;
  return {
    title: `${best.missing} card${best.missing === 1 ? "" : "s"} from finishing ${best.name}`,
    body: "Open Master Sets to see which ones you still need.",
    data: { masterSet: best.setId },
  };
}

/**
 * After the daily price check, for one person with a phone: a milestone they just reached (not
 * one already celebrated; recorded in `milestones-seen`, shared with the app and website), the
 * biggest move on one of their cards, and on Sundays the set they're closest to finishing.
 */
export async function sendCollectionPushes(admin: Admin, userId: string, data: CollectionData, today: ISODate) {
  const sent: string[] = [];
  if (!isApnsConfigured()) return sent;
  const { data: devices } = await admin.from("device_tokens").select("token, environment").eq("user_id", userId);
  if (!devices?.length) return sent;

  const { data: prefRow } = await admin.from("user_state").select("value").eq("user_id", userId).eq("key", "notification-prefs").maybeSingle();
  const prefs = readNotificationPrefs(prefRow?.value);
  if (!prefs.milestones && !prefs.bigMoves && !prefs.nearlyDone) return sent;

  const holdings = computeHoldings(data, today);
  const messages: { kind: string; message: PushMessage }[] = [];

  // Milestones: only once the app or website has started the seen list (so an old collection
  // isn't greeted by a flood), and only the best new one.
  const { data: seenRow } = await admin.from("user_state").select("value").eq("user_id", userId).eq("key", "milestones-seen").maybeSingle();
  if (prefs.milestones && seenRow && Array.isArray(seenRow.value)) {
    const seen = new Set((seenRow.value as unknown[]).filter((v): v is string => typeof v === "string"));
    const summary = summarize(holdings, totalRealized(data, today).total);
    const { show, record } = pickNew(reachedMilestones(summary, holdings), seen, false, 1);
    if (show[0]) {
      messages.push({ kind: "milestone", message: { title: show[0].title, body: show[0].description ?? "Open Dexora to see your collection." } });
      const next = [...seen, ...record];
      await admin.from("user_state").upsert({ user_id: userId, key: "milestones-seen", value: next, updated_at: new Date().toISOString() });
    }
  }

  const move = prefs.bigMoves ? bigMove(holdings) : null;
  if (move) messages.push({ kind: "move", message: move });

  if (prefs.nearlyDone && new Date(`${today}T12:00:00Z`).getUTCDay() === 0) {
    const set = await nearlyFinishedSet(admin, holdings);
    if (set) messages.push({ kind: "set", message: set });
  }

  const dead: string[] = [];
  for (const { kind, message } of messages) {
    for (const env of ["production", "sandbox"] as const) {
      const results = await sendPush((devices as Device[]).filter((d) => d.environment === env).map((d) => d.token), message, env);
      for (const r of results) {
        if (r.ok) sent.push(kind);
        else if (r.status === 410 || r.reason === "BadDeviceToken" || r.reason === "Unregistered") dead.push(r.token);
      }
    }
  }
  if (dead.length) await admin.from("device_tokens").delete().in("token", [...new Set(dead)]);
  return sent;
}
