import type { ProductCategory } from "@/lib/catalog";

const LIME = "var(--lime)";

/** A lime line drawing of what a product is: a card, pack, booster box, ETB, tin, bundle or collection box. */
export function ProductSilhouette({ category }: { category: ProductCategory }) {
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
