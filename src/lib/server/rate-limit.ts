import "server-only";

/**
 * Per-client token bucket guarding routes that spend upstream API quota.
 * In-memory per instance; good enough to stop runaway clients and typing
 * bursts. Upstream budget tracking lives in the TCG API wrapper.
 */
const buckets = new Map<string, { tokens: number; updated: number }>();

export function allowRequest(key: string, capacity = 30, refillPerMinute = 30): boolean {
  const now = Date.now();
  const b = buckets.get(key) ?? { tokens: capacity, updated: now };
  b.tokens = Math.min(capacity, b.tokens + ((now - b.updated) / 60_000) * refillPerMinute);
  b.updated = now;
  if (buckets.size > 5000) buckets.clear();
  if (b.tokens < 1) {
    buckets.set(key, b);
    return false;
  }
  b.tokens -= 1;
  buckets.set(key, b);
  return true;
}

export function clientKey(req: Request, scope: string): string {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || req.headers.get("x-real-ip") || "local";
  return `${scope}:${ip}`;
}
