import { cn } from "@/lib/utils";

/** Fey-style meter: a row of thin ticks, the leading share of them lit. */
export function TickMeter({ value, color = "var(--foreground)", ticks = 24, className }: { value: number; color?: string; ticks?: number; className?: string }) {
  const lit = Math.round(Math.max(0, Math.min(1, value)) * ticks);
  return (
    <span className={cn("inline-flex h-3 items-stretch gap-[2px]", className)} aria-hidden>
      {Array.from({ length: ticks }).map((_, i) => (
        <span key={i} className="w-[3px] rounded-[1px]" style={{ background: i < lit ? color : "var(--surface-3)", opacity: i < lit ? 0.85 : 1 }} />
      ))}
    </span>
  );
}
