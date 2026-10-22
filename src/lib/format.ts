const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 2 });
const usdCompact = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", notation: "compact", maximumFractionDigits: 1 });
const usdWhole = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });

export const MISSING = "—";

export function money(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return MISSING;
  return usd.format(n);
}

export function moneyWhole(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return MISSING;
  return usdWhole.format(n);
}

export function moneyCompact(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return MISSING;
  return Math.abs(n) < 10_000 ? usdWhole.format(n) : usdCompact.format(n);
}

export function signedMoney(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return MISSING;
  const s = usd.format(Math.abs(n));
  if (Math.abs(n) < 0.005) return s;
  return n > 0 ? `+${s}` : `−${s}`;
}

/** Format a ratio (0.1234 → 12.34%). */
export function pct(ratio: number | null | undefined, digits = 2): string {
  if (ratio === null || ratio === undefined || !Number.isFinite(ratio)) return MISSING;
  return `${(ratio * 100).toFixed(digits)}%`;
}

export function signedPct(ratio: number | null | undefined, digits = 2): string {
  if (ratio === null || ratio === undefined || !Number.isFinite(ratio)) return MISSING;
  const v = Math.abs(ratio * 100).toFixed(digits);
  if (Number(v) === 0) return `${v}%`;
  return ratio > 0 ? `+${v}%` : `−${v}%`;
}

export function tone(n: number | null | undefined): "up" | "down" | "flat" {
  if (n === null || n === undefined || !Number.isFinite(n) || Math.abs(n) < 1e-9) return "flat";
  return n > 0 ? "up" : "down";
}

const dateFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });
const shortDateFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
const monthFmt = new Intl.DateTimeFormat("en-US", { month: "short", year: "2-digit", timeZone: "UTC" });

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return MISSING;
  return dateFmt.format(new Date(iso.length === 10 ? `${iso}T00:00:00Z` : iso));
}

export function formatShortDate(iso: string): string {
  return shortDateFmt.format(new Date(`${iso.slice(0, 10)}T00:00:00Z`));
}

export function formatMonth(month: string): string {
  return monthFmt.format(new Date(`${month}-01T00:00:00Z`));
}

export function relativeTime(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return "never";
  const diff = now - Date.parse(iso);
  const min = Math.round(diff / 60_000);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m ago`;
  const h = Math.round(min / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.round(h / 24);
  return `${d}d ago`;
}
