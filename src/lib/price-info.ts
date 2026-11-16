/** "3h ago", "2d ago" for a timestamp; null when unknown. Same as the app's `PriceInfo.age`. */
export function priceAge(iso: string | null | undefined, now = Date.now()): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return null;
  const hours = Math.floor((now - t) / 3_600_000);
  if (hours < 1) return "just now";
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

/** A price more than 3 days old (shown dimmed). Same as the app's `PriceInfo.isStale`. */
export function isStalePrice(iso: string | null | undefined, now = Date.now()): boolean {
  if (!iso) return false;
  const t = Date.parse(iso);
  return Number.isFinite(t) && now - t > 3 * 86_400_000;
}
