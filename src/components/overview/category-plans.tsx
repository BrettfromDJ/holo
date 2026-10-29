"use client";

import { ArrowRight } from "lucide-react";
import Link from "next/link";
import { ProductImage } from "@/components/product/product-image";
import type { HoldingCategory, HoldingView } from "@/lib/finance/portfolio";
import { money, pct, signedMoney, signedPct } from "@/lib/format";
import { cn } from "@/lib/utils";

const PLANS: Record<HoldingCategory, { title: string; blurb: string; color: "blue" | "pink" | "lime"; href: string }> = {
  sealed: { title: "Sealed", blurb: "Boxes, ETBs, packs & collections", color: "blue", href: "/collection?kind=sealed" },
  single: { title: "Singles", blurb: "Raw cards, straight from the pack", color: "pink", href: "/collection?kind=single" },
  graded: { title: "Graded", blurb: "Slabbed and certified", color: "lime", href: "/collection?kind=graded" },
};

const BAR: Record<string, string> = { blue: "bg-[var(--plan-blue)]", pink: "bg-[var(--plan-pink)]", lime: "bg-lime" };

/**
 * Where the collection's value sits, styled like a pricing table: one bold
 * plan card per category with its top pieces, what you paid struck through
 * next to what it's worth, and a 3D button into that slice of the collection.
 */
export function CategoryPlans({ holdings }: { holdings: HoldingView[] }) {
  const total = holdings.reduce((s, h) => s + (h.value ?? 0), 0);
  const groups = (["sealed", "single", "graded"] as const)
    .map((category) => {
      const hs = holdings.filter((h) => h.category === category);
      const priced = hs.filter((h) => h.value !== null);
      const value = priced.reduce((s, h) => s + (h.value ?? 0), 0);
      const cost = priced.reduce((s, h) => s + h.costBasis, 0);
      const top = [...priced].sort((a, b) => (b.value ?? 0) - (a.value ?? 0)).slice(0, 3);
      const best = [...priced].filter((h) => h.unrealizedPct !== null).sort((a, b) => (b.unrealizedPct ?? 0) - (a.unrealizedPct ?? 0))[0];
      return { category, value, cost, share: total ? value / total : 0, products: hs.length, units: hs.reduce((s, h) => s + h.quantity, 0), top, best };
    })
    .filter((g) => g.products > 0);
  if (!groups.length) return null;

  return (
    <div>
      {/* Split bar */}
      {groups.length > 1 && (
        <div className="mb-5 flex h-9 gap-1 overflow-hidden rounded-xl">
          {groups
            .filter((g) => g.share > 0)
            .map((g) => {
              const p = PLANS[g.category];
              return (
                <div key={g.category} className={cn("flex min-w-0 animate-grow-x items-center justify-between gap-2 px-3 origin-left", BAR[p.color], p.color === "lime" ? "text-[#0b0b0c]" : "text-white")} style={{ flexGrow: g.share }}>
                  {g.share >= 0.12 && <span className="truncate font-display text-[15px] uppercase leading-none tracking-[0.02em]">{p.title}</span>}
                  <span className="tabular shrink-0 font-display text-[15px] leading-none">{pct(g.share, 0)}</span>
                </div>
              );
            })}
        </div>
      )}

      <div className={cn("grid gap-4", groups.length === 3 ? "lg:grid-cols-3" : groups.length === 2 ? "sm:grid-cols-2" : "")}>
        {groups.map((g, i) => {
          const p = PLANS[g.category];
          const gain = g.value - g.cost;
          return (
            <div key={g.category} className={cn("plan group flex flex-col rounded-[22px] p-2 animate-rise", `plan-${p.color}`)} style={{ animationDelay: `${i * 90}ms` }}>
              <div className="px-3 pt-3">
                <div className="flex flex-wrap items-center gap-2">
                  <h3 className="font-display text-[32px] uppercase leading-none tracking-[0.01em]">{p.title}</h3>
                  <span className={cn("tag-skew", `tag-${p.color === "blue" ? "blue" : p.color}`)}>{pct(g.share, 0)} of value</span>
                  {i === 0 && groups.length > 1 && g.share === Math.max(...groups.map((x) => x.share)) && <span className="tag-skew tag-white">Biggest</span>}
                </div>
                <p className="mt-1.5 text-[13px] text-foreground/60">{p.blurb}</p>
              </div>

              {/* Inner panel: the top pieces fanned out, and the numbers behind them */}
              <div className="mt-4 rounded-2xl bg-black/30 p-4 ring-1 ring-inset ring-white/[0.06]">
                <div className="relative flex h-[110px] items-center justify-center">
                  {g.top.map((h, j) => {
                    const slot = g.top.length === 1 ? 1 : g.top.length === 2 ? (j === 0 ? 0 : 2) : j;
                    return (
                      <div
                        key={h.key}
                        className={cn(
                          "absolute h-[104px] w-[76px] transition-transform duration-500 ease-[var(--ease-apple)]",
                          slot === 0 && "-translate-x-[58%] -rotate-[10deg] group-hover:-translate-x-[78%] group-hover:-rotate-[16deg]",
                          slot === 1 && "z-10 -translate-y-1 group-hover:-translate-y-3 group-hover:scale-105",
                          slot === 2 && "translate-x-[58%] rotate-[10deg] group-hover:translate-x-[78%] group-hover:rotate-[16deg]",
                        )}
                      >
                        <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} size="sm" frame={h.product?.kind !== "single"} className={cn("h-full w-full drop-shadow-[0_10px_16px_rgba(0,0,0,0.55)]", h.product?.kind !== "single" && !h.identity.grade && "rounded-xl")} />
                      </div>
                    );
                  })}
                </div>
                <ul className="mt-4 space-y-1.5 text-[13px] text-foreground/75">
                  <li className="flex items-center gap-2">
                    <span className="text-foreground/40">=</span> {g.products} product{g.products === 1 ? "" : "s"}, {g.units} item{g.units === 1 ? "" : "s"}
                  </li>
                  {g.best && (
                    <li className="flex min-w-0 items-center gap-2">
                      <span className="text-foreground/40">~</span>
                      <span className="truncate">Best: {g.best.product?.name}</span>
                      <span className={cn("tabular shrink-0 font-semibold", (g.best.unrealizedPct ?? 0) >= 0 ? "text-up" : "text-down")}>{signedPct(g.best.unrealizedPct, 0)}</span>
                    </li>
                  )}
                </ul>
              </div>

              {/* What it's worth now */}
              <p className="tabular mt-5 px-3 font-display text-[40px] leading-none">{money(g.value)}</p>

              <Link href={p.href} className={cn("btn-3d mx-1 mt-5 flex h-12 items-center justify-center gap-2 rounded-xl text-[15px] font-semibold", `btn-3d-${p.color}`, `plan-btn-${p.color}`)}>
                View {p.title.toLowerCase()} <ArrowRight className="size-4" />
              </Link>
              <p className="tabular mb-1 mt-3 text-center text-[13px] text-foreground/60">
                {g.cost > 0 ? (
                  <>
                    <span className={cn("font-semibold", gain >= 0 ? "text-up" : "text-down")}>{signedMoney(gain)}</span> on what you paid
                  </>
                ) : (
                  "No purchases recorded"
                )}
              </p>
            </div>
          );
        })}
      </div>
    </div>
  );
}
