/** Natural sort for collector numbers like "4/102", "TG05", "SWSH001". */
export function compareCollectorNumbers(a: string | null, b: string | null): number {
  if (a === b) return 0;
  if (a === null) return 1;
  if (b === null) return -1;
  return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
}
