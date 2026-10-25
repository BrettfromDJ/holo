"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";

const COLORS = ["#ff6b6b", "#ffd93d", "#6bcB77", "#4d96ff", "#c77dff", "#ff8fab", "#f5f5f7"];

interface Piece {
  id: number;
  left: number;
  delay: number;
  duration: number;
  dx: number;
  rot: number;
  color: string;
  w: number;
  h: number;
}

let burstId = 0;
type BurstListener = (count: number) => void;
const burstListeners = new Set<BurstListener>();

/** Fire a burst of confetti from the top of the screen. */
export function confetti(count = 90) {
  if (typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  for (const fn of burstListeners) fn(count);
}

/** Mount once; renders bursts requested through `confetti()`. */
export function ConfettiLayer() {
  const [pieces, setPieces] = useState<Piece[]>([]);

  useEffect(() => {
    const fn: BurstListener = (count) => {
      const batch: Piece[] = Array.from({ length: count }, () => ({
        id: burstId++,
        left: Math.random() * 100,
        delay: Math.random() * 250,
        duration: 1800 + Math.random() * 1400,
        dx: (Math.random() - 0.5) * 240,
        rot: (Math.random() - 0.5) * 1080,
        color: COLORS[Math.floor(Math.random() * COLORS.length)],
        w: 6 + Math.random() * 6,
        h: 8 + Math.random() * 10,
      }));
      setPieces((p) => [...p, ...batch]);
      const ids = new Set(batch.map((b) => b.id));
      window.setTimeout(() => setPieces((p) => p.filter((x) => !ids.has(x.id))), 3600);
    };
    burstListeners.add(fn);
    return () => {
      burstListeners.delete(fn);
    };
  }, []);

  if (!pieces.length || typeof document === "undefined") return null;
  return createPortal(
    <div aria-hidden className="pointer-events-none fixed inset-0 z-[200] overflow-hidden">
      {pieces.map((p) => (
        <span
          key={p.id}
          className="absolute -top-4 rounded-[2px]"
          style={
            {
              left: `${p.left}%`,
              width: p.w,
              height: p.h,
              background: p.color,
              animation: `confetti-fall ${p.duration}ms cubic-bezier(.2,.6,.4,1) ${p.delay}ms both`,
              "--dx": `${p.dx}px`,
              "--rot": `${p.rot}deg`,
            } as React.CSSProperties
          }
        />
      ))}
    </div>,
    document.body,
  );
}
