"use client";

import { Trophy } from "lucide-react";
import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { pickNew, reachedMilestones } from "@/lib/milestones";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useSyncedState } from "@/lib/store/synced-state";

const KEY = "holo:milestones:v1";

/**
 * Watches the collection and celebrates each milestone once with a toast.
 * Seen milestones are remembered per collection (synced when signed in).
 */
export function MilestoneWatcher() {
  const { status, repoKind, user } = useStore();
  // Milestones are about the whole collection, whichever portfolio is shown.
  const { summary, holdings } = usePortfolio({ ignoreFilter: true });
  const [stored, setStored, , synced] = useSyncedState<string[] | null>("milestones-seen", null, { legacyKey: `${KEY}:${repoKind}:${user?.id ?? "anon"}` });
  const busy = useRef(false);

  useEffect(() => {
    // Never in a demo (every fresh browser would celebrate the sample collection),
    // and only once the seen list was actually read, so a failed read never
    // repeats old milestones or saves over the account's list.
    if (repoKind === "demo" || status !== "ready" || !synced || !holdings.length || busy.current) return;
    const seen = new Set(stored ?? []);
    const { show, record } = pickNew(reachedMilestones(summary, holdings), seen, stored === null);
    if (!record.length) return;
    // Merge with whatever is stored by then (another tab or device may have added some).
    setStored((prev) => [...new Set([...(prev ?? []), ...record])]);
    busy.current = true;
    show.forEach((m, i) => {
      window.setTimeout(() => {
        toast(m.title, { description: m.description, icon: <Trophy className="size-4 text-[#ffd93d]" />, duration: 6000 });
      }, 1200 + i * 1800);
    });
    window.setTimeout(() => (busy.current = false), 1200 + show.length * 1800);
  }, [repoKind, status, synced, stored, setStored, summary, holdings]);

  return null;
}
