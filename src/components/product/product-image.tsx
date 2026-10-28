"use client";
/* eslint-disable @next/next/no-img-element -- images come from arbitrary pricing-source CDNs */
import { Layers, Package } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { categoryOf } from "@/lib/catalog";
import { slabStyle } from "@/lib/graded";
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
    | Pick<Product, "name" | "imageUrl" | "kind" | "setName" | "productType">
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
      {showImage ? (
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

/** A grading slab: clear case, colored label with the company and grade, card inside. */
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
  const style = slabStyle(grade.company);
  const tiny = size === "xs" || size === "sm";
  const text = { xs: "", sm: "", md: "text-[10px]", lg: "text-[12px]", xl: "text-[15px]" }[size];
  return (
    <div className={cn("relative flex items-center justify-center", className)} role="img" aria-label={`${product?.name ?? "Card"}, ${grade.company} ${grade.grade}`}>
      <div
        className="flex aspect-[5/8] h-full max-w-full flex-col overflow-hidden rounded-[7%/4.4%] border border-white/15 p-[5%] shadow-[0_8px_24px_rgba(0,0,0,0.45)]"
        style={{ background: "linear-gradient(160deg, rgb(255 255 255 / 0.14), rgb(255 255 255 / 0.04) 45%, rgb(255 255 255 / 0.09))" }}
      >
        <div
          className={cn("flex shrink-0 items-center justify-between rounded-[6%/30%] font-mono font-semibold leading-none", tiny ? "h-[13%]" : "h-[15%] px-[7%]", text)}
          style={{ background: style.label, color: style.text, boxShadow: `inset 0 -2px 0 ${style.accent}55` }}
        >
          {!tiny && (
            <>
              <span>{grade.company}</span>
              <span>{grade.grade}</span>
            </>
          )}
        </div>
        <div className="mt-[5%] min-h-0 flex-1">
          <ProductPhoto product={product} size={size} priority={priority} frame={false} className="h-full w-full rounded-[4%]" />
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
