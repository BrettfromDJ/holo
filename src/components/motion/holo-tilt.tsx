"use client";

import { useEffect, useRef } from "react";
import { cn } from "@/lib/utils";

/**
 * Tilts its child toward the pointer and lays a rainbow foil sheen over it,
 * like turning a holo card under a light. Works with mouse, pen and touch
 * drags; does nothing for reduced-motion users.
 *
 * On touch screens, where there's no hover, cards on screen drift on their
 * own (a slow tilt that moves the light across them); touching one hands
 * control back to your finger.
 */
export function HoloTilt({
  children,
  className,
  max = 12,
  foil = true,
  radius = "1rem",
  heroName,
}: {
  children: React.ReactNode;
  className?: string;
  /** Maximum tilt in degrees. */
  max?: number;
  foil?: boolean;
  radius?: string;
  /** View-transition name, so a card can fly into this spot from a grid. */
  heroName?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const wrap = useRef<HTMLDivElement>(null);
  const frame = useRef(0);

  // Only drift while on screen, each card at its own point in the loop.
  useEffect(() => {
    const el = wrap.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    el.style.setProperty("--holo-delay", `${(-Math.random() * 9).toFixed(2)}s`);
    const io = new IntersectionObserver(([entry]) => (el.dataset.visible = String(entry.isIntersecting)), { rootMargin: "40px" });
    io.observe(el);
    return () => io.disconnect();
  }, []);

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
      // Unitless -0.5..0.5 offsets for the moving shadow (on the wrapper, outside the tilt).
      el.parentElement?.style.setProperty("--px", String(x - 0.5));
      el.parentElement?.style.setProperty("--py", String(y - 0.5));
      el.dataset.active = "true";
      if (el.parentElement) el.parentElement.dataset.active = "true";
    });
  }

  function leave() {
    const el = ref.current;
    if (!el) return;
    cancelAnimationFrame(frame.current);
    el.style.setProperty("--rx", "0deg");
    el.style.setProperty("--ry", "0deg");
    el.parentElement?.style.setProperty("--px", "0");
    el.parentElement?.style.setProperty("--py", "0");
    el.dataset.active = "false";
    if (el.parentElement) el.parentElement.dataset.active = "false";
  }

  return (
    <div ref={wrap} className={cn("holo-tilt relative isolate", className)} data-active="false" data-visible="false" onPointerMove={move} onPointerLeave={leave} onPointerCancel={leave} style={{ perspective: "900px", viewTransitionName: heroName }}>
      {/* Shadow on the "table": slides opposite the tilt, as if lit from above. */}
      <span aria-hidden className="holo-shadow" style={{ borderRadius: radius }} />
      <div ref={ref} className="holo-tilt-inner relative h-full w-full" data-active="false" style={{ borderRadius: radius }}>
        {children}
        {foil && <span aria-hidden className="holo-foil" style={{ borderRadius: radius }} />}
        <span aria-hidden className="holo-glare" style={{ borderRadius: radius }} />
      </div>
    </div>
  );
}

/** Cards whose rarity or name suggests a holo, foil or special-art finish. */
export function isFoilCard(p: { kind?: string; rarity?: string | null; name?: string } | undefined): boolean {
  if (!p || p.kind !== "single") return false;
  return /holo|foil|secret|illustration|full art|alternate|alt art|rainbow|gold|hyper|ultra|special|v(max|star)\b|\bex\b|\bgx\b|shiny|prism/i.test(`${p.rarity ?? ""} ${p.name ?? ""}`);
}
