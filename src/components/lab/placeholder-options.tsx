"use client";

import { Camera } from "lucide-react";
import { categoryOf, type ProductCategory } from "@/lib/catalog";
import type { Product } from "@/lib/types";
import { cn } from "@/lib/utils";

/**
 * Prototype placeholders for products without a photo, compared on /lab/placeholders.
 * Each fills its box; `compact` is the small list-thumbnail size, where text is dropped.
 */

export type PlaceholderProduct = Pick<Product, "name" | "kind" | "setName" | "productType">;
type Props = { product: PlaceholderProduct; compact?: boolean };

const LIME = "var(--lime)";

function Caption({ product }: { product: PlaceholderProduct }) {
  return (
    <div className="max-w-full text-center">
      <p className="truncate font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">{categoryOf(product)}</p>
      <p className="mt-0.5 truncate text-[11px] text-muted">{product.setName ?? product.name}</p>
    </div>
  );
}

/* A. Card outline (what's live now) */
export function OptionCardOutline({ product, compact }: Props) {
  const card = <span aria-hidden className="block aspect-[63/88] h-full rounded-[9%/6.5%] border-[1.5px] border-[var(--lime)] bg-[color-mix(in_srgb,var(--lime)_10%,transparent)] shadow-[0_0_14px_-4px_var(--lime)]" />;
  return compact ? (
    <div className="flex h-full items-center justify-center">
      <span className="h-[62%]">{card}</span>
    </div>
  ) : (
    <div className="flex h-full flex-col items-center justify-center gap-[6%] p-[12%]">
      <span className="h-[46%]">{card}</span>
      <Caption product={product} />
    </div>
  );
}

/* B. Shape by product type: a lime line drawing of a card, pack, box, ETB, tin or bundle */
function Silhouette({ category }: { category: ProductCategory }) {
  const s = { fill: "color-mix(in srgb, var(--lime) 9%, transparent)", stroke: LIME, strokeWidth: 1.6, strokeLinejoin: "round" as const, vectorEffect: "non-scaling-stroke" as const };
  const line = { fill: "none", stroke: LIME, strokeWidth: 1.2, strokeOpacity: 0.6, vectorEffect: "non-scaling-stroke" as const };
  switch (category) {
    case "Card":
      return (
        <svg viewBox="0 0 64 88" className="h-full">
          <rect x="1" y="1" width="62" height="86" rx="5" {...s} />
          <rect x="7" y="9" width="50" height="34" rx="2" {...line} />
          <path d="M7 52h50M7 60h34M7 68h42" {...line} />
        </svg>
      );
    case "Booster Pack":
      return (
        <svg viewBox="0 0 60 92" className="h-full">
          <path d="M2 8 l4 -6 l4 6 l4 -6 l4 6 l4 -6 l4 6 l4 -6 l4 6 l4 -6 l4 6 l4 -6 l4 6 l4 -6 l4 6 V84 l-4 6 l-4 -6 l-4 6 l-4 -6 l-4 6 l-4 -6 l-4 6 l-4 -6 l-4 6 l-4 -6 l-4 6 l-4 -6 l-4 6 l-4 -6 Z" {...s} />
          <path d="M2 16h56M2 76h56" {...line} />
          <circle cx="30" cy="44" r="12" {...line} />
        </svg>
      );
    case "Booster Box":
      return (
        <svg viewBox="0 0 100 70" className="w-full">
          <path d="M8 22 L28 6 H92 L72 22 Z" {...s} />
          <path d="M72 22 L92 6 V50 L72 66 Z" {...s} />
          <rect x="8" y="22" width="64" height="44" {...s} />
          <path d="M8 34h64" {...line} />
        </svg>
      );
    case "Elite Trainer Box":
      return (
        <svg viewBox="0 0 80 90" className="h-full">
          <path d="M6 20 L20 8 H74 L60 20 Z" {...s} />
          <path d="M60 20 L74 8 V74 L60 86 Z" {...s} />
          <rect x="6" y="20" width="54" height="66" {...s} />
          <path d="M6 38h54" {...line} />
          <rect x="20" y="50" width="26" height="24" rx="2" {...line} />
        </svg>
      );
    case "Tin":
      return (
        <svg viewBox="0 0 80 90" className="h-full">
          <rect x="6" y="14" width="68" height="72" rx="12" {...s} />
          <rect x="3" y="6" width="74" height="18" rx="8" {...s} />
          <circle cx="40" cy="54" r="14" {...line} />
        </svg>
      );
    case "Booster Bundle":
      return (
        <svg viewBox="0 0 96 80" className="w-full">
          {[0, 1, 2].map((i) => (
            <rect key={i} x={10 + i * 18} y={4 + (i % 2) * 6} width="40" height="62" rx="3" transform={`rotate(${(i - 1) * 8} ${30 + i * 18} 40)`} {...s} />
          ))}
        </svg>
      );
    default:
      // Ultra Premium Collection, Collection Box, Other Sealed: a wide box with a window.
      return (
        <svg viewBox="0 0 110 72" className="w-full">
          <path d="M6 20 L22 6 H104 L88 20 Z" {...s} />
          <path d="M88 20 L104 6 V54 L88 68 Z" {...s} />
          <rect x="6" y="20" width="82" height="48" {...s} />
          <rect x="18" y="30" width="34" height="28" rx="2" {...line} />
          <path d="M60 34h20M60 42h14" {...line} />
        </svg>
      );
  }
}

export function OptionShape({ product, compact }: Props) {
  const cat = categoryOf(product);
  return compact ? (
    <div className="flex h-full items-center justify-center p-[18%]">
      <div className="flex h-full w-full items-center justify-center">
        <Silhouette category={cat} />
      </div>
    </div>
  ) : (
    <div className="flex h-full flex-col items-center justify-center gap-[7%] p-[12%]">
      <div className="flex h-[46%] w-[72%] items-center justify-center">
        <Silhouette category={cat} />
      </div>
      <Caption product={product} />
    </div>
  );
}

/* C. Holo card back: a branded card back, like the back of a real card */
export function OptionCardBack({ product, compact }: Props) {
  return (
    <div className={cn("flex h-full items-center justify-center", compact ? "p-[14%]" : "p-[10%]")}>
      <div className="card-back relative flex aspect-[63/88] h-full max-w-full items-center justify-center overflow-hidden rounded-[7%/5%]">
        <svg viewBox="0 0 32 32" className="w-[44%] drop-shadow-[0_0_10px_var(--lime)]" aria-hidden>
          <circle cx="16" cy="16" r="12" fill="#0b0b0c" stroke={LIME} strokeWidth="2.5" />
          <path d="M4 16h24" stroke={LIME} strokeWidth="2.5" />
          <circle cx="16" cy="16" r="4" fill="#0b0b0c" stroke={LIME} strokeWidth="2.5" />
        </svg>
        {!compact && <span className="absolute inset-x-0 bottom-[7%] truncate px-[10%] text-center font-display text-[11px] uppercase tracking-[0.08em] text-[var(--lime)]/80">{categoryOf(product)}</span>}
      </div>
    </div>
  );
}

/* D. Title card: a lime proxy card with the product's name printed on it */
export function OptionTitleCard({ product, compact }: Props) {
  return (
    <div className={cn("flex h-full items-center justify-center", compact ? "p-[14%]" : "p-[10%]")}>
      <div className="relative flex aspect-[63/88] h-full max-w-full flex-col overflow-hidden rounded-[7%/5%] bg-[var(--lime)] p-[9%] text-[#0b0b0c] shadow-[0_10px_30px_-12px_var(--lime)]" style={{ containerType: "inline-size" }}>
        {compact ? (
          <span className="m-auto font-display text-[46cqw] leading-none">{(product.setName ?? product.name).slice(0, 1)}</span>
        ) : (
          <>
            <span className="font-mono text-[6.5cqw] font-bold uppercase tracking-[0.08em] opacity-60">{categoryOf(product)}</span>
            <span className="mt-auto line-clamp-4 font-display text-[15cqw] uppercase leading-[0.92]">{product.name}</span>
            <span className="mt-[6%] truncate text-[7cqw] font-semibold opacity-70">{product.setName}</span>
          </>
        )}
      </div>
    </div>
  );
}

/* E. Monogram: the set's initials in big display type */
function initials(text: string) {
  const words = text.replace(/[^A-Za-z0-9 ]/g, " ").split(/\s+/).filter((w) => w && !/^(and|of|the|&)$/i.test(w));
  return (words.length > 1 ? words[0][0] + words[1][0] : (words[0] ?? "?").slice(0, 2)).toUpperCase();
}
export function OptionMonogram({ product, compact }: Props) {
  return (
    <div className="flex h-full flex-col items-center justify-center p-[10%]" style={{ containerType: "size" }}>
      <span className="font-display leading-none text-[var(--lime)] drop-shadow-[0_0_18px_color-mix(in_srgb,var(--lime)_45%,transparent)]" style={{ fontSize: compact ? "52cqh" : "34cqh" }}>
        {initials(product.setName ?? product.name)}
      </span>
      {!compact && (
        <div className="mt-[8%] w-full">
          <Caption product={product} />
        </div>
      )}
    </div>
  );
}

/* F. Dashed frame with "Add photo": says what's missing and invites a fix */
export function OptionAddPhoto({ product, compact }: Props) {
  return (
    <div className={cn("flex h-full items-center justify-center", compact ? "p-[16%]" : "p-[10%]")}>
      <div className="flex aspect-[63/88] h-full max-w-full flex-col items-center justify-center gap-[8%] rounded-[7%/5%] border-[1.5px] border-dashed border-[var(--lime)]/70 bg-[color-mix(in_srgb,var(--lime)_6%,transparent)] text-[var(--lime)]">
        <Camera className={compact ? "size-[46%]" : "size-[22%]"} strokeWidth={1.5} />
        {!compact && (
          <>
            <span className="text-[12px] font-semibold">Add photo</span>
            <span className="max-w-[80%] truncate text-[10px] text-muted">{product.setName}</span>
          </>
        )}
      </div>
    </div>
  );
}
