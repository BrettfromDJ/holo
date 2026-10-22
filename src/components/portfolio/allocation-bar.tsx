import type { AllocationSlice, HoldingCategory } from "@/lib/finance/portfolio";
import { money, pct } from "@/lib/format";

export const CATEGORY_META: Record<HoldingCategory, { label: string; color: string }> = {
  sealed: { label: "Sealed", color: "var(--cat-1)" },
  single: { label: "Singles", color: "var(--cat-2)" },
  graded: { label: "Graded", color: "var(--cat-3)" },
};

/** Part-to-whole as one segmented bar with 2px gaps, plus a labeled legend. */
export function AllocationBar({ slices, showCost }: { slices: AllocationSlice[]; showCost?: boolean }) {
  const visible = slices.filter((s) => s.value > 0 || s.count > 0);
  return (
    <div>
      <div className="flex h-2 w-full gap-[2px] overflow-hidden rounded-full" role="img" aria-label={visible.map((s) => `${CATEGORY_META[s.category].label} ${pct(s.share, 0)}`).join(", ")}>
        {visible
          .filter((s) => s.share > 0)
          .map((s) => (
            <div key={s.category} className="h-full first:rounded-l-full last:rounded-r-full transition-[flex-grow] duration-700" style={{ flexGrow: s.share, background: CATEGORY_META[s.category].color }} />
          ))}
        {!visible.some((s) => s.share > 0) && <div className="h-full flex-1 bg-surface-2" />}
      </div>
      <ul className="mt-4 divide-y divide-border">
        {visible.map((s) => (
          <li key={s.category} className="flex items-center gap-3 py-2 text-[13px]">
            <span className="size-2 rounded-[2px]" style={{ background: CATEGORY_META[s.category].color }} aria-hidden />
            <span className="flex-1">
              {CATEGORY_META[s.category].label} <span className="text-muted">· {s.count}</span>
            </span>
            {showCost && <span className="tabular hidden w-28 text-right text-muted sm:block">{money(s.costBasis)} cost</span>}
            <span className="tabular w-24 text-right font-semibold">{money(s.value)}</span>
            <span className="tabular w-12 text-right text-muted">{pct(s.share, 0)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
