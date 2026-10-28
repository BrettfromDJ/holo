"use client";

import { useLayoutEffect, useRef } from "react";

/**
 * FLIP reordering: when a grid's items change order (sort, filter), tiles that
 * stay glide from their old spot to the new one instead of jumping. Children
 * opt in with `data-flip-key`. Positions are measured relative to the
 * container, so scrolling between renders doesn't matter.
 */
export function useFlip<T extends HTMLElement>(deps: unknown) {
  const ref = useRef<T>(null);
  const last = useRef(new Map<string, { x: number; y: number }>());

  useLayoutEffect(() => {
    const root = ref.current;
    if (!root) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const next = new Map<string, { x: number; y: number }>();
    for (const el of root.querySelectorAll<HTMLElement>("[data-flip-key]")) {
      const key = el.dataset.flipKey!;
      const pos = { x: el.offsetLeft, y: el.offsetTop };
      next.set(key, pos);
      const prev = last.current.get(key);
      if (reduce || !prev || (prev.x === pos.x && prev.y === pos.y)) continue;
      el.animate([{ transform: `translate(${prev.x - pos.x}px, ${prev.y - pos.y}px)` }, { transform: "none" }], { duration: 450, easing: "cubic-bezier(0.32, 0.72, 0, 1)" });
    }
    last.current = next;
  }, [deps]);

  return ref;
}
