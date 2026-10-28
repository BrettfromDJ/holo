"use client";
/* eslint-disable @next/next/no-img-element -- images come from arbitrary pricing-source CDNs */
import { Layers, Package } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { categoryOf } from "@/lib/catalog";
import { isFoilCard } from "@/components/motion/holo-tilt";
import { gradeDescriptor, slabStyle } from "@/lib/graded";
import type { Grade, Product } from "@/lib/types";
import { cn } from "@/lib/utils";

const HUES = [210, 265, 330, 20, 45, 160, 190, 290];

function hueFor(text: string) {
  let h = 0;
  for (let i = 0; i < text.length; i++) h = (h * 31 + text.charCodeAt(i)) >>> 0;
  return HUES[h % HUES.length];
}

/**
 * Product photography in a neutral "well". When a product has no image (or
 * it fails to load) we render a restrained, clearly-generic placeholder —
 * never a stand-in photo of a different product.
 */
export function ProductImage({
  product,
  className,
  size = "md",
  priority,
  frame = true,
  grade,
}: {
  product:
    | (Pick<Product, "name" | "imageUrl" | "kind" | "setName" | "productType"> & Partial<Pick<Product, "number" | "rarity">>)
    | undefined;
  className?: string;
  size?: "xs" | "sm" | "md" | "lg" | "xl";
  priority?: boolean;
  /** False draws the image edge to edge with no well behind it (e.g. a bare card). */
  frame?: boolean;
  /** A graded card is drawn inside a slab with its grading label. */
  grade?: Grade | null;
}) {
  if (grade) return <Slab product={product} grade={grade} size={size} priority={priority} className={className} />;
  return <ProductPhoto product={product} size={size} priority={priority} frame={frame} className={className} />;
}

function ProductPhoto({
  product,
  className,
  size,
  priority,
  frame,
}: {
  product: Parameters<typeof ProductImage>[0]["product"];
  className?: string;
  size: NonNullable<Parameters<typeof ProductImage>[0]["size"]>;
  priority?: boolean;
  frame: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);
  // Server-rendered images can fail before React attaches onError; catch that on mount.
  useEffect(() => {
    const img = imgRef.current;
    if (img && img.complete && img.naturalWidth === 0) setFailed(true);
  }, []);
  const pad = { xs: "p-1", sm: "p-1.5", md: "p-3", lg: "p-5", xl: "p-8" }[size];
  const showImage = product?.imageUrl && !failed;
  // Single cards are never framed: just the card, at its own shape, with rounded corners.
  const bare = Boolean(showImage) && (!frame || product?.kind === "single");

  return (
    <div
      className={cn(
        "relative flex items-center justify-center overflow-hidden rounded-2xl",
        !bare && "bg-image-well",
        className,
      )}
    >
      {showImage && bare && product.kind === "single" ? (
        // A bare card gets a printed-card finish: grain, a fine print pattern, a sheen and an edge.
        <span className="relative inline-flex h-full max-w-full">
          <img
            ref={imgRef}
            src={product.imageUrl!}
            alt={product.name}
            loading={priority ? "eager" : "lazy"}
            decoding="async"
            onError={() => setFailed(true)}
            className="h-full w-auto max-w-full rounded-[4.5%/3.2%] object-contain shadow-[0_8px_24px_rgba(0,0,0,0.45)] transition-transform duration-500 ease-[var(--ease-apple)]"
          />
          <span aria-hidden className={cn("card-texture pointer-events-none absolute inset-0 rounded-[4.5%/3.2%]", isFoilCard(product) && "is-foil")} />
        </span>
      ) : showImage ? (
        <img
          ref={imgRef}
          src={product.imageUrl!}
          alt={product.name}
          loading={priority ? "eager" : "lazy"}
          decoding="async"
          onError={() => setFailed(true)}
          className={cn(
            "transition-transform duration-500 ease-[var(--ease-apple)]",
            bare
              ? "h-full w-auto max-w-full rounded-[4.5%/3.2%] object-contain shadow-[0_8px_24px_rgba(0,0,0,0.45)]"
              : cn(
                  "h-full w-full object-contain drop-shadow-[0_8px_16px_rgba(0,0,0,0.35)]",
                  pad,
                ),
          )}
        />
      ) : (
        <Placeholder product={product} size={size} />
      )}
    </div>
  );
}

/**
 * A grading slab, drawn to scale with its own width (container units): a
 * thick clear case with a bevel and glare, a printed label (company, card,
 * grade and its wording, barcode) and the card in a recessed window.
 */
function Slab({
  product,
  grade,
  size,
  priority,
  className,
}: {
  product: Parameters<typeof ProductImage>[0]["product"];
  grade: Grade;
  size: NonNullable<Parameters<typeof ProductImage>[0]["size"]>;
  priority?: boolean;
  className?: string;
}) {
  const style = slabStyle(grade);
  const tiny = size === "xs" || size === "sm";
  const details = [product?.setName, product?.number ? `#${product.number}` : null].filter(Boolean).join(" · ");
  return (
    <div className={cn("relative flex items-center justify-center", className)} role="img" aria-label={`${product?.name ?? "Card"}, ${grade.company} ${grade.grade}`}>
      <div className="group/slab relative aspect-[5/8] h-full max-w-full [container-type:inline-size]">
        {/* The case: clear acrylic with a lit top edge and a darker base. */}
        <div
          className="absolute inset-0 rounded-[7cqw]"
          style={{
            background: "linear-gradient(155deg, rgb(255 255 255 / 0.26), rgb(255 255 255 / 0.08) 22%, rgb(255 255 255 / 0.04) 55%, rgb(255 255 255 / 0.14))",
            boxShadow:
              "inset 0 0 0 1px rgb(255 255 255 / 0.22), inset 0 1.5px 0 rgb(255 255 255 / 0.45), inset 0 -1.2cqw 3cqw rgb(0 0 0 / 0.35), 0 4cqw 9cqw -2cqw rgb(0 0 0 / 0.7), 0 1cqw 2cqw rgb(0 0 0 / 0.35)",
          }}
        />
        {/* The inner step where the insert sits. */}
        <div className="absolute inset-[2.2cqw] rounded-[5cqw] ring-1 ring-inset ring-white/10" />

        <div className={cn("absolute flex flex-col", tiny ? "inset-[6cqw] gap-[5cqw]" : "inset-[4.5cqw] gap-[3.5cqw]")}>
          {/* Label */}
          <div
            className={cn("relative shrink-0 overflow-hidden rounded-[2.4cqw]", tiny ? "h-[16cqw]" : "h-[27cqw]")}
            style={{ background: style.label, color: style.text, boxShadow: `inset 0 ${tiny ? "2.5cqw" : "1.1cqw"} 0 ${style.accent}, 0 0.5cqw 1.5cqw rgb(0 0 0 / 0.35)` }}
          >
            {!tiny && (
              <div className="flex h-full items-stretch gap-[3cqw] px-[4cqw] pb-[2.6cqw] pt-[3.4cqw]">
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="text-[6.4cqw] font-black leading-none tracking-[-0.02em]" style={{ color: style.accent }}>
                    {grade.company}
                  </span>
                  <span className="mt-[1.6cqw] truncate text-[3.3cqw] font-bold uppercase leading-tight">{product?.name ?? "Card"}</span>
                  {details && <span className="truncate text-[2.8cqw] font-medium uppercase leading-tight opacity-60">{details}</span>}
                  {/* Barcode */}
                  <span
                    aria-hidden
                    className="mt-auto block h-[3cqw] w-[55%] opacity-70"
                    style={{ background: `repeating-linear-gradient(90deg, currentColor 0 0.35cqw, transparent 0.35cqw 0.7cqw, currentColor 0.7cqw 1.4cqw, transparent 1.4cqw 1.75cqw, currentColor 1.75cqw 1.95cqw, transparent 1.95cqw 2.6cqw)` }}
                  />
                </div>
                <div className="flex shrink-0 flex-col items-end justify-center text-right">
                  <span className="text-[2.9cqw] font-bold uppercase leading-none tracking-[0.04em] opacity-75">{gradeDescriptor(grade)}</span>
                  <span className="mt-[1cqw] text-[12cqw] font-black leading-[0.85] tracking-[-0.04em]">{grade.grade}</span>
                </div>
              </div>
            )}
          </div>

          {/* Card window */}
          <div
            className="relative min-h-0 flex-1 rounded-[3cqw] p-[3.5cqw]"
            style={{ background: "linear-gradient(180deg, rgb(0 0 0 / 0.45), rgb(0 0 0 / 0.3))", boxShadow: "inset 0 0.8cqw 2.5cqw rgb(0 0 0 / 0.6), inset 0 0 0 1px rgb(255 255 255 / 0.06)" }}
          >
            <ProductPhoto product={product} size={size} priority={priority} frame={false} className="h-full w-full rounded-[2cqw]" />
          </div>
        </div>

        {/* Glare across the acrylic; drifts on hover. */}
        <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden rounded-[7cqw]">
          <div
            className="absolute -inset-[40%] translate-x-[-12%] transition-transform duration-700 ease-[var(--ease-apple)] group-hover/slab:translate-x-[12%]"
            style={{ background: "linear-gradient(115deg, transparent 40%, rgb(255 255 255 / 0.13) 47%, rgb(255 255 255 / 0.04) 52%, transparent 58%)" }}
          />
        </div>
      </div>
    </div>
  );
}

function Placeholder({
  product,
  size,
}: {
  product: Parameters<typeof ProductImage>[0]["product"];
  size: string;
}) {
  const name = product?.name ?? "Product";
  const hue = hueFor(product?.setName ?? name);
  const sealed = product?.kind === "sealed";
  const label = product
    ? categoryOf({
        name,
        productType: product.productType ?? null,
        kind: product.kind,
      })
    : "";
  const Icon = sealed ? Package : Layers;
  const tint = `hsl(${hue} 30% 60%)`;
  if (size === "xs" || size === "sm") {
    return (
      <div
        className="flex h-full w-full items-center justify-center"
        role="img"
        aria-label={`${name} (no image available)`}
      >
        <Icon
          className="size-[42%] max-h-6 max-w-6 opacity-80"
          style={{ color: tint }}
          strokeWidth={1.5}
        />
      </div>
    );
  }
  return (
    <div
      className="flex h-full w-full flex-col items-center justify-center gap-[6%] p-[12%]"
      role="img"
      aria-label={`${name} (no image available)`}
    >
      <div
        className={cn(
          "flex items-center justify-center border",
          sealed
            ? "aspect-[4/3] w-[62%] rounded-[12%]"
            : "aspect-[63/88] w-[46%] rounded-[8%]",
        )}
        style={{
          borderColor: `hsl(${hue} 20% 50% / 0.35)`,
          background: `hsl(${hue} 25% 50% / 0.06)`,
        }}
      >
        <Icon
          className="size-[30%] opacity-70"
          style={{ color: tint }}
          strokeWidth={1.25}
        />
      </div>
      <div className="max-w-full text-center">
        <p className="truncate text-[10px] font-medium font-mono uppercase tracking-[0.06em] text-subtle">
          {label}
        </p>
        <p className="mt-0.5 truncate text-[11px] text-muted">
          {product?.setName ?? name}
        </p>
      </div>
    </div>
  );
}
