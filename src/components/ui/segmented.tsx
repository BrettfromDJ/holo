"use client";
import * as ToggleGroup from "@radix-ui/react-toggle-group";
import { cn } from "@/lib/utils";

/** iOS-style segmented control built on Radix ToggleGroup (single select). */
export function Segmented<T extends string>({
  value,
  onChange,
  options,
  className,
  size = "md",
  ariaLabel,
}: {
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: React.ReactNode; title?: string }[];
  className?: string;
  size?: "sm" | "md";
  ariaLabel: string;
}) {
  return (
    <ToggleGroup.Root
      type="single"
      value={value}
      onValueChange={(v) => v && onChange(v as T)}
      aria-label={ariaLabel}
      className={cn("inline-flex items-center gap-0.5 rounded-full bg-surface-2 p-1", className)}
    >
      {options.map((o) => (
        <ToggleGroup.Item
          key={o.value}
          value={o.value}
          title={o.title}
          aria-label={o.title}
          className={cn(
            "inline-flex items-center justify-center gap-1.5 rounded-full font-medium text-muted transition-all duration-200 ease-[var(--ease-apple)] hover:text-foreground data-[state=on]:bg-surface-3 data-[state=on]:text-foreground data-[state=on]:shadow-sm [&_svg]:size-4",
            size === "sm" ? "h-7 px-2.5 text-xs" : "h-8 px-3.5 text-[13px]",
          )}
        >
          {o.label}
        </ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}
