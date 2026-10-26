"use client";

import { BellRing } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo } from "react";
import { toast } from "sonner";
import { useExploreIndex } from "@/components/explore/explore-items";
import { daysUntil, useReleaseReminders, whenLabel } from "@/lib/reminders";
import { useStore } from "@/lib/store/collection-store";

/** Reminded sets releasing in the next 30 days (or the last 3), shown on Overview. */
export function ReleaseReminders() {
  const { slugs } = useReleaseReminders();
  return slugs.length ? <Reminders slugs={slugs} /> : null;
}

function Reminders({ slugs }: { slugs: string[] }) {
  const index = useExploreIndex();
  const { today } = useStore();
  const due = useMemo(() => {
    if (index.status !== "ready") return [];
    return index.sets
      .filter((s) => slugs.includes(s.slug) && s.releaseDate)
      .map((s) => ({ set: s, days: daysUntil(s.releaseDate!, today) }))
      .filter((x) => x.days >= -3 && x.days <= 30)
      .sort((a, b) => a.days - b.days);
  }, [index, slugs, today]);

  // A one-time toast on release day.
  useEffect(() => {
    for (const { set, days } of due) {
      if (days !== 0) continue;
      const key = `holo:release-toast:${set.slug}`;
      try {
        if (localStorage.getItem(key)) continue;
        localStorage.setItem(key, "1");
      } catch {
        continue;
      }
      toast(`${set.name} is out today`, { description: set.gameName, icon: <BellRing className="size-4" /> });
    }
  }, [due]);

  if (!due.length) return null;
  return (
    <section aria-label="Release reminders" className="mb-8 flex flex-wrap gap-2">
      {due.map(({ set, days }) => (
        <Link
          key={set.slug}
          href={set.loaded ? `/explore/${encodeURIComponent(set.slug)}` : "/explore/releases"}
          className="inline-flex items-center gap-2 rounded-full border border-border bg-surface py-1.5 pl-3 pr-4 text-[13px] transition-colors hover:bg-surface-2"
        >
          <BellRing className="size-3.5 text-muted" />
          <span className="font-medium">{set.name}</span>
          <span className="text-muted">· {whenLabel(days)}</span>
        </Link>
      ))}
    </section>
  );
}
