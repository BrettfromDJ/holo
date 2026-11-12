import { Diff } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Marks a figure we worked out rather than saw sold: a soft blue pill with a ± mark. Quiet, but
 * clearly a label (no dotted outline, no ≈). Same as the app's EstimatePill.
 */
export function EstimatePill({ className, children = "Estimate" }: { className?: string; children?: React.ReactNode }) {
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center gap-1 rounded-full bg-[color-mix(in_srgb,var(--plan-blue)_20%,transparent)] py-0.5 pl-1.5 pr-2 text-[11px] font-semibold leading-tight text-foreground/90 ring-[0.5px] ring-inset ring-[color-mix(in_srgb,var(--plan-blue)_35%,transparent)]",
        className,
      )}
    >
      <Diff className="size-3 text-[#8fa6ff]" strokeWidth={2.5} aria-hidden />
      {children}
    </span>
  );
}
