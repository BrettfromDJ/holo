import { ArrowDownRight, ArrowUpRight } from "lucide-react";
import { signedMoney, signedPct, tone } from "@/lib/format";
import { cn } from "@/lib/utils";

/** Colored gain/loss text. Neutral when zero or unknown. */
export function Delta({
  value,
  ratio,
  className,
  showIcon,
  pctOnly,
  digits = 2,
}: {
  value?: number | null;
  ratio?: number | null;
  className?: string;
  showIcon?: boolean;
  pctOnly?: boolean;
  digits?: number;
}) {
  const t = tone(value ?? ratio ?? null);
  const color = t === "up" ? "text-up" : t === "down" ? "text-down" : "text-muted";
  const Icon = t === "down" ? ArrowDownRight : ArrowUpRight;
  return (
    <span className={cn("tabular inline-flex items-center gap-0.5 whitespace-nowrap", color, className)}>
      {showIcon && t !== "flat" && <Icon className="size-[1em]" aria-hidden />}
      {!pctOnly && value !== undefined && <span>{signedMoney(value)}</span>}
      {ratio !== undefined && (pctOnly || value === undefined ? <span>{signedPct(ratio, digits)}</span> : <span className="opacity-80">({signedPct(ratio, digits)})</span>)}
    </span>
  );
}

/** Pill used on cards for compact percentage changes. */
export function DeltaPill({ ratio, className }: { ratio: number | null | undefined; className?: string }) {
  const t = tone(ratio);
  return (
    <span
      className={cn(
        "tabular inline-flex items-center justify-center rounded-[5px] px-1.5 py-[3px] text-[11px] font-medium leading-none",
        t === "up" ? "bg-up-soft text-up" : t === "down" ? "bg-down-soft text-down" : "bg-surface-2 text-muted",
        className,
      )}
    >
      {signedPct(ratio)}
    </span>
  );
}
