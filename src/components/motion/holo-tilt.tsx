"use client";

import { useRef } from "react";
import { cn } from "@/lib/utils";

/**
 * Tilts its child toward the pointer and lays a rainbow foil sheen over it,
 * like turning a holo card under a light. Works with mouse, pen and touch
 * drags; does nothing for reduced-motion users.
 */
export function HoloTilt({
  children,
  className,
  max = 12,
  foil = true,
  radius = "1rem",
}: {
  children: React.ReactNode;
  className?: string;
  /** Maximum tilt in degrees. */
  max?: number;
  foil?: boolean;
  radius?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const frame = useRef(0);

  function move(e: React.PointerEvent) {
    const el = ref.current;
    if (!el || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const r = el.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width;
    const y = (e.clientY - r.top) / r.height;
    cancelAnimationFrame(frame.current);
    frame.current = requestAnimationFrame(() => {
      el.style.setProperty("--rx", `${(0.5 - y) * max}deg`);
      el.style.setProperty("--ry", `${(x - 0.5) * max}deg`);
      el.style.setProperty("--mx", `${x * 100}%`);
      el.style.setProperty("--my", `${y * 100}%`);
      el.dataset.active = "true";
    });
  }

  function leave() {
    const el = ref.current;
    if (!el) return;
    cancelAnimationFrame(frame.current);
    el.style.setProperty("--rx", "0deg");
    el.style.setProperty("--ry", "0deg");
    el.dataset.active = "false";
  }

  return (
    <div className={cn("holo-tilt", className)} onPointerMove={move} onPointerLeave={leave} onPointerCancel={leave} style={{ perspective: "900px" }}>
      <div ref={ref} className="holo-tilt-inner relative h-full w-full" data-active="false" style={{ borderRadius: radius }}>
        {children}
        {foil && <span aria-hidden className="holo-foil" style={{ borderRadius: radius }} />}
        <span aria-hidden className="holo-glare" style={{ borderRadius: radius }} />
      </div>
    </div>
  );
}
