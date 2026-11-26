"use client";

import { cn } from "@/lib/utils";

/**
 * The app's ChipPicker: separate rounded (13px) glass tiles with a faint light edge and white
 * text, the selected one filled white with dark text; no track behind them. The row scrolls
 * inside its margins with the right edge fading when it doesn't fit.
 */
export function ChipTiles<T extends string>({
  value,
  onChange,
  options,
  ariaLabel,
  className,
  size = "md",
}: {
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: React.ReactNode }[];
  ariaLabel: string;
  className?: string;
  size?: "sm" | "md";
}) {
  return (
    <div
      role="radiogroup"
      aria-label={ariaLabel}
      className={cn(
        "flex gap-2 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden",
        // Fades the right edge so a cut-off chip reads as "scroll for more".
        "[mask-image:linear-gradient(to_right,black_calc(100%-28px),transparent)] pr-6",
        className,
      )}
    >
      {options.map((o) => {
        const on = o.value === value;
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={on}
            onClick={() => onChange(o.value)}
            className={cn(
              "shrink-0 whitespace-nowrap rounded-[13px] border font-medium transition-colors",
              size === "sm" ? "h-8 px-3 text-[13px]" : "h-9 px-3.5 text-[14px]",
              on ? "border-white bg-white text-[#0b0b0c]" : "border-white/10 bg-white/[0.06] text-white backdrop-blur-xl hover:bg-white/[0.1]",
            )}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
