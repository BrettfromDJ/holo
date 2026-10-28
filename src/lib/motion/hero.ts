"use client";

import { useRouter } from "next/navigation";
import { useCallback, useLayoutEffect, useState } from "react";

/**
 * Shared-element ("hero") transitions: tapping a card makes its image fly into
 * place on the product page instead of cutting to a new page. Uses the
 * browser's View Transitions API; where it isn't supported (or Reduce Motion
 * is on) links simply navigate.
 */

const NAME = "product-hero";
let pending: (() => void) | null = null;

function supported() {
  return typeof document !== "undefined" && "startViewTransition" in document && !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** Click handler for a card link. `lift` first raises the card (pulling it out of a binder pocket). */
export function useHeroLink(opts?: { lift?: boolean }) {
  const router = useRouter();
  const lift = opts?.lift;
  return useCallback(
    (e: React.MouseEvent<HTMLElement>, href: string) => {
      if (!supported() || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      e.preventDefault();
      const link = e.currentTarget;
      const target = link.querySelector<HTMLElement>(".holo-tilt") ?? link.querySelector<HTMLElement>("img") ?? link;
      const go = () => {
        target.style.viewTransitionName = NAME;
        const t = document.startViewTransition(
          () =>
            new Promise<void>((resolve) => {
              pending = resolve;
              router.push(href);
              // If the product page takes a while (loading from the catalog), crossfade instead.
              window.setTimeout(resolve, 800);
            }),
        );
        t.finished.finally(() => {
          target.style.viewTransitionName = "";
          target.classList.remove("pocket-lift");
        });
      };
      if (lift) {
        target.classList.add("pocket-lift");
        window.setTimeout(go, 170);
      } else go();
    },
    [router, lift],
  );
}

/**
 * On the product page: names its hero image and tells a running transition the
 * page is ready. `arriving` is true when the page was opened by a hero
 * transition, so its own entrance animation can step aside.
 */
export function useHeroTarget(ready: boolean) {
  const [arriving] = useState(() => pending !== null);
  useLayoutEffect(() => {
    if (!ready || !pending) return;
    const done = pending;
    pending = null;
    done();
  }, [ready]);
  return { name: NAME, arriving };
}
