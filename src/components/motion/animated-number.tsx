"use client";

import { useEffect, useRef, useState } from "react";

function prefersReducedMotion() {
  return typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}

/**
 * Counts from the previously shown value to `value` (ease-out). The first
 * render counts up from `from`. Set `animate={false}` for instant updates,
 * e.g. while scrubbing a chart.
 */
export function AnimatedNumber({
  value,
  format,
  duration = 900,
  from = 0,
  animate = true,
}: {
  value: number;
  format: (n: number) => React.ReactNode;
  duration?: number;
  from?: number;
  animate?: boolean;
}) {
  const [shown, setShown] = useState(animate ? from : value);
  const shownRef = useRef(shown);
  shownRef.current = shown;

  useEffect(() => {
    if (!animate || prefersReducedMotion()) return setShown(value);
    const start = shownRef.current;
    if (start === value) return;
    let raf = 0;
    const t0 = performance.now();
    const tick = (now: number) => {
      const p = Math.min(1, (now - t0) / duration);
      const eased = 1 - Math.pow(1 - p, 4);
      setShown(start + (value - start) * eased);
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value, animate, duration]);

  return <>{format(animate ? shown : value)}</>;
}
