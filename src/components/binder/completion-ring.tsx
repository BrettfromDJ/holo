"use client";

import { useInView } from "@/components/motion/reveal";
import { cn } from "@/lib/utils";

/** Progress ring that sweeps to `value` (0–1) when it scrolls into view. */
export function CompletionRing({ value, size = 64, stroke = 6, className, children }: { value: number | null; size?: number; stroke?: number; className?: string; children?: React.ReactNode }) {
  const [ref, inView] = useInView<HTMLDivElement>();
  const r = (size - stroke) / 2;
  const pct = Math.max(0, Math.min(1, value ?? 0));
  const done = pct >= 1;
  return (
    <div ref={ref} className={cn("relative shrink-0", className)} style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--surface-3)" strokeWidth={stroke} />
        {value !== null && (
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke={done ? "url(#ring-holo)" : "var(--foreground)"}
            strokeWidth={stroke}
            strokeLinecap="round"
            pathLength={1}
            strokeDasharray={1}
            strokeDashoffset={inView ? 1 - pct : 1}
            style={{ transition: "stroke-dashoffset 1.2s var(--ease-apple)" }}
          />
        )}
        <defs>
          <linearGradient id="ring-holo" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#ff7ab6" />
            <stop offset="35%" stopColor="#ffd36e" />
            <stop offset="65%" stopColor="#6ef0c2" />
            <stop offset="100%" stopColor="#7aa8ff" />
          </linearGradient>
        </defs>
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">{children}</div>
    </div>
  );
}
