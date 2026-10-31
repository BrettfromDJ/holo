import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../supabase/database.types";
import { getAdminSupabase, getRequestUser } from "../supabase/server";

const HOUR = 60 * 60 * 1000;

/**
 * The answer to a paid TCG API call, shared by every server through the database for `ttlMs`
 * (a day by default). Each server's own memory cache is lost whenever Vercel starts a fresh
 * one, so without this the same answer was paid for again and again. `ttlMs` can depend on
 * the answer (keep an empty one only briefly, so it's asked again soon).
 */
export async function dbCached<T>(key: string, load: () => Promise<T>, ttlMs: number | ((value: T) => number) = 24 * HOUR): Promise<T> {
  const admin = getAdminSupabase();
  if (!admin) return load();
  const db = admin as unknown as SupabaseClient<Database>;
  const { data: hit } = await db.from("api_cache").select("value, expires_at").eq("key", key).maybeSingle();
  if (hit && Date.parse(hit.expires_at) > Date.now()) return hit.value as T;
  const value = await load();
  const ttl = typeof ttlMs === "function" ? ttlMs(value) : ttlMs;
  if (ttl <= 0) return value;
  // Saving is best effort: a failed write just means the next look pays again.
  await db.from("api_cache").upsert({ key, value: value as never, expires_at: new Date(Date.now() + ttl).toISOString() }).then(
    () => undefined,
    () => undefined,
  );
  return value;
}

/** Daily limits per person for the actions that spend paid TCG API calls. */
export const DAILY_LIMITS = {
  scan: Number(process.env.LIMIT_SCANS_PER_DAY) || 150,
  liveSearch: Number(process.env.LIMIT_LIVE_SEARCHES_PER_DAY) || 40,
  history: Number(process.env.LIMIT_HISTORY_LOADS_PER_DAY) || 150,
} as const;

/**
 * Count one paid action for whoever is asking (their account, or their address when signed
 * out) and say whether it's within today's limit. Without a database it always allows.
 */
export async function takeQuota(req: Request, action: keyof typeof DAILY_LIMITS): Promise<boolean> {
  const admin = getAdminSupabase();
  if (!admin) return true;
  const user = await getRequestUser().catch(() => null);
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || req.headers.get("x-real-ip") || "local";
  const who = user ? `user:${user.id}` : `ip:${ip}`;
  const { data, error } = await (admin as unknown as SupabaseClient<Database>).rpc("take_quota", { p_who: who, p_action: action, p_limit: DAILY_LIMITS[action] });
  // If the counter itself fails, don't lock people out.
  return error ? true : Boolean(data);
}

export function overLimit(what: string) {
  return { error: { code: "daily_limit", message: `You've reached today's limit for ${what}. It resets tomorrow.` } };
}
