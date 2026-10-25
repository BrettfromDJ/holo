"use client";

import { Trophy } from "lucide-react";
import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { pickNew, reachedMilestones } from "@/lib/milestones";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { confetti } from "./confetti";

const KEY = "holo:milestones:v1";

/**
 * Watches the collection and celebrates each milestone once: a toast plus a
 * little confetti. Seen milestones are remembered per collection in this
 * browser.
 */
export function MilestoneWatcher() {
  const { status, repoKind, user } = useStore();
  const { summary, holdings } = usePortfolio();
  const busy = useRef(false);

  useEffect(() => {
    if (status !== "ready" || !holdings.length || busy.current) return;
    const key = `${KEY}:${repoKind}:${user?.id ?? "anon"}`;
    let stored: string[] | null = null;
    try {
      const raw = localStorage.getItem(key);
      stored = raw ? (JSON.parse(raw) as string[]) : null;
    } catch {
      return;
    }
    const seen = new Set(stored ?? []);
    const { show, record } = pickNew(reachedMilestones(summary, holdings), seen, stored === null);
    if (!record.length) return;
    try {
      localStorage.setItem(key, JSON.stringify([...seen, ...record]));
    } catch {
      return;
    }
    busy.current = true;
    show.forEach((m, i) => {
      window.setTimeout(() => {
        toast(m.title, { description: m.description, icon: <Trophy className="size-4 text-[#ffd93d]" />, duration: 6000 });
        if (i === 0) confetti(60);
      }, 1200 + i * 1800);
    });
    window.setTimeout(() => (busy.current = false), 1200 + show.length * 1800);
  }, [status, repoKind, user, summary, holdings]);

  return null;
}
