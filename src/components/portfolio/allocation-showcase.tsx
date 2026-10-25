import Link from "next/link";
import { DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import type { HoldingCategory, HoldingView } from "@/lib/finance/portfolio";
import { money, pct } from "@/lib/format";
import { cn } from "@/lib/utils";
import { CATEGORY_META } from "./allocation-bar";

interface CategoryGroup {
  category: HoldingCategory;
  value: number;
  costBasis: number;
  share: number;
  products: number;
  units: number;
  top: HoldingView[];
}

const ORDER: HoldingCategory[] = ["sealed", "single", "graded"];
const FAN = [
  "-rotate-[8deg] -translate-x-[48%]",
  "rotate-0 z-10 -translate-y-1",
  "rotate-[8deg] translate-x-[48%]",
];
const FAN_HOVER = [
  "group-hover:-rotate-[13deg] group-hover:-translate-x-[62%]",
  "group-hover:-translate-y-2.5",
  "group-hover:rotate-[13deg] group-hover:translate-x-[62%]",
];

function groupHoldings(holdings: HoldingView[]): CategoryGroup[] {
  const total = holdings.reduce((s, h) => s + (h.value ?? 0), 0);
  return ORDER.map((category) => {
    const hs = holdings.filter((h) => h.category === category);
    const priced = hs.filter((h) => h.value !== null);
    const value = priced.reduce((s, h) => s + (h.value ?? 0), 0);
    return {
      category,
      value,
      costBasis: priced.reduce((s, h) => s + h.costBasis, 0),
      share: total > 0 ? value / total : 0,
      products: hs.length,
      units: hs.reduce((s, h) => s + h.quantity, 0),
      top: [...priced]
        .sort((a, b) => (b.value ?? 0) - (a.value ?? 0))
        .slice(0, 3),
    };
  }).filter((g) => g.products > 0);
}

/**
 * Collection split as photo-forward tiles: a proportional bar, then one
 * tile per category with a fanned stack of its most valuable products, its
 * value, share and (optionally) performance.
 */
export function AllocationShowcase({
  holdings,
  showGains = true,
  linkTiles = true,
}: {
  holdings: HoldingView[];
  showGains?: boolean;
  linkTiles?: boolean;
}) {
  const groups = groupHoldings(holdings);
  if (!groups.length)
    return <p className="py-6 text-[14px] text-muted">Nothing to show yet.</p>;
  const filterFor: Record<HoldingCategory, string> = {
    sealed: "sealed",
    single: "single",
    graded: "graded",
  };

  return (
    <div>
      <div
        className="flex h-7 w-full origin-left animate-grow-x gap-[3px] overflow-hidden rounded-[10px]"
        role="img"
        aria-label={groups
          .map((g) => `${CATEGORY_META[g.category].label} ${pct(g.share, 0)}`)
          .join(", ")}
      >
        {groups
          .filter((g) => g.share > 0)
          .map((g) => (
            <div
              key={g.category}
              className="flex min-w-0 items-center overflow-hidden px-2.5 transition-[flex-grow] duration-700 ease-[var(--ease-apple)]"
              style={{
                flexGrow: g.share,
                background: CATEGORY_META[g.category].color,
              }}
            >
              {g.share >= 0.12 && (
                <span className="tabular truncate text-[12px] font-semibold text-white/95">
                  {pct(g.share, 0)}
                </span>
              )}
            </div>
          ))}
      </div>

      <div
        className={cn(
          "mt-5 grid gap-3",
          groups.length === 1
            ? "grid-cols-1"
            : groups.length === 2
              ? "grid-cols-2"
              : "grid-cols-1 sm:grid-cols-3",
        )}
      >
        {groups.map((g) => {
          const gainPct =
            g.costBasis > 0 ? (g.value - g.costBasis) / g.costBasis : null;
          const body = (
            <div className="flex items-center gap-4 sm:block">
              <div className="relative flex h-[84px] w-[132px] shrink-0 items-center justify-center sm:h-[104px] sm:w-auto">
                {g.top.length ? (
                  g.top.map((h, i) => {
                    const slot =
                      g.top.length === 1
                        ? 1
                        : g.top.length === 2
                          ? i === 0
                            ? 0
                            : 2
                          : i;
                    return (
                      <div
                        key={h.key}
                        className={cn(
                          "absolute size-[56px] transition-transform sm:size-[76px] duration-500 ease-[var(--ease-apple)] will-change-transform",
                          FAN[slot],
                          FAN_HOVER[slot],
                        )}
                      >
                        <ProductImage
                          product={h.product}
                          size="sm"
                          className="h-full w-full rounded-xl shadow-lg shadow-black/40 ring-1 ring-border"
                        />
                      </div>
                    );
                  })
                ) : (
                  <span className="text-[12px] text-subtle">No prices yet</span>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 sm:mt-3">
                  <span
                    className="size-2 rounded-full"
                    style={{ background: CATEGORY_META[g.category].color }}
                    aria-hidden
                  />
                  <span className="text-[13px] font-medium">
                    {CATEGORY_META[g.category].label}
                  </span>
                  <span className="tabular ml-auto text-[12px] text-muted">
                    {pct(g.share, 0)}
                  </span>
                </div>
                <p className="tabular mt-1 text-[22px] font-semibold tracking-tight">
                  {money(g.value)}
                </p>
                <div className="mt-1 flex items-center justify-between gap-2">
                  <span
                    className="tabular truncate text-[12px] text-muted"
                    title={`${g.units} item${g.units === 1 ? "" : "s"}`}
                  >
                    {g.products} product{g.products === 1 ? "" : "s"}
                  </span>
                  {showGains && <DeltaPill ratio={gainPct} />}
                </div>
              </div>
            </div>
          );
          const cls =
            "group block rounded-2xl bg-surface-2/60 p-4 transition-colors duration-300 hover:bg-surface-2";
          return linkTiles ? (
            <Link
              key={g.category}
              href={`/collection?kind=${filterFor[g.category]}`}
              className={cls}
              aria-label={`${CATEGORY_META[g.category].label}: ${money(g.value)}, ${pct(g.share, 0)} of collection`}
            >
              {body}
            </Link>
          ) : (
            <div key={g.category} className={cls}>
              {body}
            </div>
          );
        })}
      </div>
    </div>
  );
}
