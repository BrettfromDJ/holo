"use client";
/* eslint-disable @next/next/no-img-element -- images come from arbitrary pricing-source CDNs */

import { useState } from "react";
import type { Product } from "@/lib/types";
import { hueFor } from "./product-image";

/**
 * Atmospheric page backdrop: the product's own photo, heavily blurred and
 * darkened, fading into the page background. Falls back to a soft glow in
 * the product's hue when there's no photo (or it fails to load).
 */
export function ProductBackdrop({ product }: { product: Pick<Product, "imageUrl" | "name" | "setName"> }) {
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);
  const hue = hueFor(product.setName ?? product.name);
  const showImage = product.imageUrl && !failed;

  return (
    <div
      aria-hidden
      className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[760px] overflow-hidden"
      style={{ maskImage: "linear-gradient(to bottom, black 0%, black 45%, transparent 100%)", WebkitMaskImage: "linear-gradient(to bottom, black 0%, black 45%, transparent 100%)" }}
    >
      {/* Colour glow is always present: it's the fallback and warms the edges of the photo. */}
      <div className="absolute inset-0 animate-backdrop" style={{ background: `radial-gradient(70% 60% at 30% 25%, hsl(${hue} 45% 32% / 0.55), transparent 70%)` }} />
      {showImage && (
        <img
          src={product.imageUrl!}
          alt=""
          onLoad={() => setLoaded(true)}
          onError={() => setFailed(true)}
          className="absolute left-1/2 top-[-12%] h-[130%] w-[130%] max-w-none -translate-x-1/2 object-cover blur-[64px] saturate-[1.4] transition-opacity duration-[1200ms] ease-[var(--ease-apple)]"
          style={{ opacity: loaded ? 0.55 : 0 }}
        />
      )}
      {/* Darken so text stays readable on any photo. */}
      <div className="absolute inset-0 bg-gradient-to-b from-background/45 via-background/60 to-background" />
    </div>
  );
}
