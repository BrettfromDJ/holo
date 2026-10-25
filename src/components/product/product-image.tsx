"use client";
/* eslint-disable @next/next/no-img-element -- images come from arbitrary pricing-source CDNs */
import { Layers, Package } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { categoryOf } from "@/lib/catalog";
import type { Product } from "@/lib/types";
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
}: {
  product:
    | Pick<Product, "name" | "imageUrl" | "kind" | "setName" | "productType">
    | undefined;
  className?: string;
  size?: "xs" | "sm" | "md" | "lg" | "xl";
  priority?: boolean;
  /** False draws the image edge to edge with no well behind it (e.g. a bare card). */
  frame?: boolean;
}) {
  // 0 = background-removed version (sealed), 1 = original, 2 = failed.
  const [stage, setStage] = useState(0);
  const imgRef = useRef<HTMLImageElement>(null);
  const cutout = product?.kind === "sealed" && Boolean(product.imageUrl) && /^https:/.test(product.imageUrl ?? "");
  const src = product?.imageUrl ? (cutout && stage === 0 ? `/api/img?u=${encodeURIComponent(product.imageUrl)}` : product.imageUrl) : null;
  const fail = () => setStage((s) => (s === 0 && cutout ? 1 : 2));
  const failed = stage === 2 || (stage === 1 && !cutout);
  // Server-rendered images can fail before React attaches onError; catch that on mount.
  useEffect(() => {
    const img = imgRef.current;
    if (img && img.complete && img.naturalWidth === 0) fail();
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
          src={src!}
          alt={product.name}
          loading={priority ? "eager" : "lazy"}
          decoding="async"
          onError={fail}
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
        <p className="truncate text-[10px] font-semibold uppercase tracking-[0.14em] text-subtle">
          {label}
        </p>
        <p className="mt-0.5 truncate text-[11px] text-muted">
          {product?.setName ?? name}
        </p>
      </div>
    </div>
  );
}
