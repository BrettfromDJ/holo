"use client";

import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

/** True once the element has scrolled into view (stays true). */
export function useInView<T extends Element>(rootMargin = "0px 0px -8% 0px") {
  const ref = useRef<T>(null);
  const [inView, setInView] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el || inView) return;
    if (typeof IntersectionObserver === "undefined") return setInView(true);
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setInView(true);
          io.disconnect();
        }
      },
      { rootMargin },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [inView, rootMargin]);
  return [ref, inView] as const;
}

/**
 * Fades and lifts its children into place the first time they scroll into
 * view. `delay` (ms) staggers neighbours. Reduced-motion users get no motion
 * (the global prefers-reduced-motion rule collapses durations).
 */
export function Reveal({ children, delay = 0, className, as: Tag = "div" }: { children: React.ReactNode; delay?: number; className?: string; as?: "div" | "section" }) {
  const [ref, inView] = useInView<HTMLDivElement>();
  return (
    <Tag
      ref={ref}
      className={cn("transition-[opacity,transform] duration-700 ease-[var(--ease-apple)] will-change-transform", inView ? "translate-y-0 opacity-100" : "translate-y-4 opacity-0", className)}
      style={{ transitionDelay: inView ? `${delay}ms` : "0ms" }}
    >
      {children}
    </Tag>
  );
}
