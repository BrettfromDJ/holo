import type { ChartRange, ISODate } from "../types";

const DAY_MS = 86_400_000;

function toUTC(date: ISODate): number {
  const [y, m, d] = date.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

function fromUTC(ms: number): ISODate {
  return new Date(ms).toISOString().slice(0, 10);
}

/** Today's calendar date in the local time zone. */
export function todayISO(now: Date = new Date()): ISODate {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function addDays(date: ISODate, days: number): ISODate {
  return fromUTC(toUTC(date) + days * DAY_MS);
}

export function daysBetween(from: ISODate, to: ISODate): number {
  return Math.round((toUTC(to) - toUTC(from)) / DAY_MS);
}

/** Inclusive list of every calendar day between two dates. */
export function eachDay(from: ISODate, to: ISODate): ISODate[] {
  const out: ISODate[] = [];
  const n = daysBetween(from, to);
  for (let i = 0; i <= n; i++) out.push(addDays(from, i));
  return out;
}

export function minDate(a: ISODate, b: ISODate): ISODate {
  return a < b ? a : b;
}

export function maxDate(a: ISODate, b: ISODate): ISODate {
  return a > b ? a : b;
}

const RANGE_DAYS: Record<Exclude<ChartRange, "ALL">, number> = {
  "1D": 1,
  "1W": 7,
  "1M": 30,
  "3M": 91,
  "1Y": 365,
};

/** First date shown for a chart range. `ALL` starts at the earliest activity. */
export function rangeStart(range: ChartRange, today: ISODate, earliest: ISODate): ISODate {
  if (range === "ALL") return minDate(earliest, today);
  return addDays(today, -RANGE_DAYS[range]);
}

export function monthKey(date: ISODate): string {
  return date.slice(0, 7);
}
