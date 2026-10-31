"use client";

import { useEffect } from "react";

/**
 * Rows that scroll sideways (chip and tab rows, marked `fade-row`) fade out on the right while
 * there's more to scroll to, like the app, and show plainly when everything fits or you've
 * reached the end. One listener for the whole page; it only toggles a data attribute.
 */
export function FadeRows() {
  useEffect(() => {
    const update = (el: Element) => {
      const e = el as HTMLElement;
      const more = e.scrollWidth - e.clientWidth - e.scrollLeft > 2;
      if ((e.dataset.fadeEnd === "true") !== more) e.dataset.fadeEnd = String(more);
    };
    // Page changes (new rows, resizes) re-check every row, at most a few times a second.
    let timer: ReturnType<typeof setTimeout> | undefined;
    const all = () => {
      if (timer) return;
      timer = setTimeout(() => {
        timer = undefined;
        document.querySelectorAll(".fade-row").forEach(update);
      }, 150);
    };
    const onScroll = (ev: Event) => {
      const t = ev.target;
      if (t instanceof HTMLElement && t.classList.contains("fade-row")) update(t);
    };
    all();
    const ro = new ResizeObserver(all);
    ro.observe(document.body);
    const mo = new MutationObserver(all);
    mo.observe(document.body, { childList: true, subtree: true });
    document.addEventListener("scroll", onScroll, { capture: true, passive: true });
    return () => {
      ro.disconnect();
      mo.disconnect();
      document.removeEventListener("scroll", onScroll, { capture: true });
      if (timer) clearTimeout(timer);
    };
  }, []);
  return null;
}
