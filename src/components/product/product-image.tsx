"use client";
/* eslint-disable @next/next/no-img-element -- images come from arbitrary pricing-source CDNs */
import { Layers, Package } from "lucide-react";
import { useState } from "react";
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
}: {
  product: Pick<Product, "name" | "imageUrl" | "kind" | "setName" | "productType"> | undefined;
  className?: string;
  size?: "xs" | "sm" | "md" | "lg" | "xl";
  priority?: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const pad = { xs: "p-1", sm: "p-1.5", md: "p-3", lg: "p-5", xl: "p-8" }[size];
  const showImage = product?.imageUrl && !failed;

  return (
    <div className={cn("relative flex items-center justify-center overflow-hidden rounded-xl bg-image-well", className)}>
      {showImage ? (
        <img
          src={product.imageUrl!}
          alt={product.name}
          loading={priority ? "eager" : "lazy"}
          decoding="async"
          onError={() => setFailed(true)}
          className={cn("h-full w-full object-contain drop-shadow-[0_8px_16px_rgba(0,0,0,0.35)] transition-transform duration-500 ease-[var(--ease-apple)]", pad)}
        />
      ) : (
        <Placeholder product={product} size={size} />
      )}
    </div>
  );
}

function Placeholder({ product, size }: { product: Parameters<typeof ProductImage>[0]["product"]; size: string }) {
  const name = product?.name ?? "Product";
  const hue = hueFor(product?.setName ?? name);
  const sealed = product?.kind === "sealed";
  const label = product ? categoryOf({ name, productType: product.productType ?? null, kind: product.kind }) : "";
  const Icon = sealed ? Package : Layers;
  const tint = `hsl(${hue} 30% 60%)`;
  if (size === "xs" || size === "sm") {
    return (
      <div className="flex h-full w-full items-center justify-center" role="img" aria-label={`${name} (no image available)`}>
        <Icon className="size-[42%] max-h-6 max-w-6 opacity-80" style={{ color: tint }} strokeWidth={1.5} />
      </div>
    );
  }
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-[6%] p-[12%]" role="img" aria-label={`${name} (no image available)`}>
      <div
        className={cn("flex items-center justify-center border", sealed ? "aspect-[4/3] w-[62%] rounded-[12%]" : "aspect-[63/88] w-[46%] rounded-[8%]")}
        style={{ borderColor: `hsl(${hue} 20% 50% / 0.35)`, background: `hsl(${hue} 25% 50% / 0.06)` }}
      >
        <Icon className="size-[30%] opacity-70" style={{ color: tint }} strokeWidth={1.25} />
      </div>
      <div className="max-w-full text-center">
        <p className="truncate text-[10px] font-semibold uppercase tracking-[0.14em] text-subtle">{label}</p>
        <p className="mt-0.5 truncate text-[11px] text-muted">{product?.setName ?? name}</p>
      </div>
    </div>
  );
}
