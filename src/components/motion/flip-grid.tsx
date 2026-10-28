"use client";

import { Children, isValidElement } from "react";
import { useFlip } from "@/lib/motion/flip";
import { cn } from "@/lib/utils";

/**
 * A grid whose tiles cascade in on first load and glide to their new spots
 * when the order changes (sorting, filtering), instead of jumping.
 */
export function FlipGrid({ className, children }: { className?: string; children: React.ReactNode }) {
  const order = Children.map(children, (c) => (isValidElement(c) ? String(c.key) : ""))?.join("|") ?? "";
  const ref = useFlip<HTMLDivElement>(order);
  return (
    <div ref={ref} className={cn("relative", className)}>
      {children}
    </div>
  );
}

/** One tile in a FlipGrid. `index` staggers its entrance. */
export function FlipItem({ flipKey, index, className, children }: { flipKey: string; index: number; className?: string; children: React.ReactNode }) {
  return (
    <div data-flip-key={flipKey} className={cn("animate-rise", className)} style={{ animationDelay: `${Math.min(index, 16) * 35}ms` }}>
      {children}
    </div>
  );
}
