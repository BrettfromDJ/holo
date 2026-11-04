/**
 * A stopwatch for one request: `lap(name)` records how long the step since the last lap took.
 * The laps go back to the app in the response (and into the Vercel log) so a slow scan says
 * where its seconds went. `cold` is true for the first request this server instance answers:
 * that one also paid the function's wake-up, which isn't in any lap.
 */

let answered = false;

export class Stopwatch {
  readonly cold: boolean;
  private readonly start = performance.now();
  private last = this.start;
  private readonly laps: Record<string, number> = {};

  constructor() {
    this.cold = !answered;
    answered = true;
  }

  /** Records the step since the last lap (or the start) as `name`, in whole milliseconds. */
  lap(name: string): void {
    const now = performance.now();
    this.laps[name] = Math.round(now - this.last);
    this.last = now;
  }

  /** Every lap plus the total so far and whether this was a cold start. */
  report(): Record<string, number | boolean> {
    return { ...this.laps, total: Math.round(performance.now() - this.start), cold: this.cold };
  }

  /** The same figures as a `Server-Timing` header value, for the browser's network panel. */
  header(): string {
    const parts = Object.entries(this.laps).map(([k, v]) => `${k};dur=${v}`);
    parts.push(`total;dur=${Math.round(performance.now() - this.start)}`);
    if (this.cold) parts.push("cold");
    return parts.join(", ");
  }
}
