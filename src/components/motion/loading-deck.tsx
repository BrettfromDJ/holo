"use client";

import { useEffect, useState } from "react";
import { cn } from "@/lib/utils";

/**
 * The loading screen (port of the app's `LoadingView`): three cards fanned on a lit grid,
 * shuffling in a loop (the front card tucks to the back and the next springs forward with a
 * lime edge, a lime glow and a foil sweep), over a rotating collector's caption.
 * Cheap: only transform and opacity animate; shadows are constant layers whose opacity flips.
 * With reduced motion the cards rest and only the caption changes.
 */

const CAPTIONS = [
  "Shuffling your binder…",
  "Checking today's prices…",
  "Polishing the slabs…",
  "Counting your grails…",
  "Sleeving the hits…",
  "Opening the vault…",
];

const TINTS = ["var(--plan-blue)", "var(--plan-pink)", "var(--lime)"];
// Back, middle, front.
const ROT = [-12, -2, 9];
const X = [-38, -6, 30];
const Y = [8, 0, -8];
const SCALE = [0.9, 0.95, 1.04];

function useReducedMotion() {
  const [reduce, setReduce] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia?.("(prefers-reduced-motion: reduce)");
    if (!mq) return;
    setReduce(mq.matches);
    const on = () => setReduce(mq.matches);
    mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, []);
  return reduce;
}

export function LoadingDeck({ className }: { className?: string }) {
  const reduce = useReducedMotion();
  const [step, setStep] = useState(0);
  const [caption, setCaption] = useState(0);

  useEffect(() => {
    if (reduce) {
      setStep(0);
      return;
    }
    const id = window.setInterval(() => setStep((s) => (s + 1) % 3), 1100);
    return () => window.clearInterval(id);
  }, [reduce]);

  useEffect(() => {
    const id = window.setInterval(() => setCaption((c) => (c + 1) % CAPTIONS.length), 1600);
    return () => window.clearInterval(id);
  }, []);

  return (
    <div role="status" aria-label="Loading" className={cn("loading-deck relative isolate flex w-full flex-col items-center justify-center py-28 sm:py-36", className)}>
      <style>{CSS}</style>
      <div aria-hidden className="loading-deck-bg pointer-events-none absolute inset-x-0 -inset-y-16 -z-10" />
      <div aria-hidden className="relative h-[170px] w-[200px]">
        {[0, 1, 2].map((i) => {
          const slot = (i + step) % 3;
          const front = slot === 2;
          return (
            <div
              key={i}
              className="loading-deck-slot absolute left-1/2 top-1/2"
              style={{
                zIndex: slot,
                transform: `translate(-50%, -50%) translate(${X[slot]}px, ${Y[slot]}px) rotate(${ROT[slot]}deg) scale(${SCALE[slot]})`,
              }}
            >
              <LoaderCard front={front} tint={TINTS[i]} />
            </div>
          );
        })}
      </div>
      <div aria-hidden className="mt-[34px] h-5">
        <p key={caption} className="loading-deck-caption text-[15px] font-medium leading-5 text-muted">
          {CAPTIONS[caption]}
        </p>
      </div>
    </div>
  );
}

function LoaderCard({ front, tint }: { front: boolean; tint: string }) {
  return (
    <div className="relative h-[128px] w-[92px]">
      {/* Constant shadows; only their opacity changes. */}
      <div className="absolute inset-0 rounded-[12px] shadow-[0_6px_28px_rgb(0_0_0/0.4)] transition-opacity duration-500" style={{ opacity: front ? 0 : 1 }} />
      <div
        className="absolute inset-0 rounded-[12px] transition-opacity duration-500"
        style={{ opacity: front ? 1 : 0, boxShadow: "0 6px 28px color-mix(in srgb, var(--lime) 45%, transparent)" }}
      />
      <div className="absolute inset-0 overflow-hidden rounded-[12px] bg-surface-2">
        <div className="absolute inset-0" style={{ background: `radial-gradient(110px circle at 50% 0%, color-mix(in srgb, ${tint} 35%, transparent), transparent)` }} />
        {/* A simple card face: art window and two lines. */}
        <div className="absolute inset-[10px] flex flex-col gap-1.5">
          <div className="h-[70px] rounded-[6px] bg-white/[0.07]" />
          <div className="h-[5px] rounded-full bg-white/[0.12]" />
          <div className="h-[5px] w-10 rounded-full bg-white/[0.08]" />
        </div>
        <div className="absolute inset-0 transition-opacity duration-300" style={{ opacity: front ? 1 : 0 }}>
          <div className="loading-deck-sweep absolute inset-y-0 left-1/2 w-[220px]" />
        </div>
      </div>
      <div className="absolute inset-0 rounded-[12px] border border-border transition-opacity duration-300" style={{ opacity: front ? 0 : 1 }} />
      <div className="absolute inset-0 rounded-[12px] border-[1.5px] border-[var(--lime)] transition-opacity duration-300" style={{ opacity: front ? 1 : 0 }} />
    </div>
  );
}

const CSS = `
.loading-deck-bg {
  background:
    radial-gradient(circle 220px at 50% 50%, color-mix(in srgb, var(--lime) 18%, transparent), transparent),
    radial-gradient(circle 180px at 80% 30%, color-mix(in srgb, var(--plan-pink) 10%, transparent), transparent),
    radial-gradient(circle 180px at 20% 75%, color-mix(in srgb, var(--plan-blue) 12%, transparent), transparent),
    linear-gradient(to right, color-mix(in srgb, var(--foreground) 6%, transparent) 1px, transparent 1px) center / 28px 28px,
    linear-gradient(to bottom, color-mix(in srgb, var(--foreground) 6%, transparent) 1px, transparent 1px) center / 28px 28px;
  -webkit-mask-image: radial-gradient(circle 320px at 50% 50%, #000 40px, transparent);
  mask-image: radial-gradient(circle 320px at 50% 50%, #000 40px, transparent);
}
.loading-deck-slot {
  transition: transform 650ms cubic-bezier(0.34, 1.45, 0.64, 1);
  will-change: transform;
}
.loading-deck-sweep {
  margin-left: -110px;
  background: linear-gradient(90deg, transparent 30%, rgb(255 255 255 / 0.35) 50%, transparent 70%);
  mix-blend-mode: plus-lighter;
  animation: loading-deck-sweep 1.4s ease-in-out infinite;
}
@keyframes loading-deck-sweep {
  from { transform: translateX(-140px); }
  to { transform: translateX(140px); }
}
.loading-deck-caption { animation: loading-deck-fade 350ms ease-in-out both; }
@keyframes loading-deck-fade {
  from { opacity: 0; }
  to { opacity: 1; }
}
@media (prefers-reduced-motion: reduce) {
  .loading-deck-slot { transition: none; }
  .loading-deck-sweep { animation: none; opacity: 0; }
}
`;
