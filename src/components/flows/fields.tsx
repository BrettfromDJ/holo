"use client";

import { Minus, Plus } from "lucide-react";
import { useId } from "react";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

export function Field({ label, hint, children, className, htmlFor }: { label: string; hint?: React.ReactNode; children: React.ReactNode; className?: string; htmlFor?: string }) {
  return (
    <div className={cn("flex flex-col gap-1.5", className)}>
      <div className="flex items-baseline justify-between gap-2">
        <Label htmlFor={htmlFor}>{label}</Label>
        {hint && <span className="text-[13px] text-subtle">{hint}</span>}
      </div>
      {children}
    </div>
  );
}

/** Currency input that keeps the raw string so users can type freely. */
export function MoneyInput({
  value,
  onChange,
  id,
  placeholder = "0.00",
  autoFocus,
  ariaLabel,
}: {
  value: string;
  onChange: (v: string) => void;
  id?: string;
  placeholder?: string;
  autoFocus?: boolean;
  ariaLabel?: string;
}) {
  return (
    <div className="relative">
      <span className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-[15px] text-subtle">$</span>
      <input
        id={id}
        inputMode="decimal"
        autoComplete="off"
        autoFocus={autoFocus}
        aria-label={ariaLabel}
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, "").replace(/(\..*)\./g, "$1"))}
        className="tabular h-11 w-full rounded-2xl border border-border bg-surface-2 pl-7 pr-3.5 text-[15px] outline-none placeholder:text-subtle focus:border-border-strong focus:bg-surface-3"
      />
    </div>
  );
}

export function Stepper({ value, onChange, min = 1, max = 9999, label }: { value: number; onChange: (n: number) => void; min?: number; max?: number; label: string }) {
  const id = useId();
  return (
    <div className="flex h-11 items-center rounded-2xl border border-border bg-surface-2">
      <button type="button" aria-label={`Decrease ${label}`} onClick={() => onChange(Math.max(min, value - 1))} className="flex h-full w-11 items-center justify-center text-muted hover:text-foreground disabled:opacity-30" disabled={value <= min}>
        <Minus className="size-4" />
      </button>
      <input
        id={id}
        aria-label={label}
        inputMode="numeric"
        value={Number.isFinite(value) ? String(value) : ""}
        onChange={(e) => {
          const n = parseInt(e.target.value.replace(/\D/g, ""), 10);
          onChange(Number.isFinite(n) ? Math.min(max, n) : 0);
        }}
        onBlur={() => value < min && onChange(min)}
        className="tabular h-full min-w-0 flex-1 bg-transparent text-center text-[15px] font-medium outline-none"
      />
      <button type="button" aria-label={`Increase ${label}`} onClick={() => onChange(Math.min(max, value + 1))} className="flex h-full w-11 items-center justify-center text-muted hover:text-foreground disabled:opacity-30" disabled={value >= max}>
        <Plus className="size-4" />
      </button>
    </div>
  );
}

export function parseMoney(s: string): number | null {
  if (s.trim() === "") return null;
  const n = Number(s);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 10000) / 10000 : null;
}

export function SummaryRow({ label, value, strong }: { label: string; value: React.ReactNode; strong?: boolean }) {
  return (
    <div className={cn("flex items-center justify-between text-[15px]", strong ? "font-semibold text-foreground" : "text-muted")}>
      <span>{label}</span>
      <span className="tabular">{value}</span>
    </div>
  );
}
