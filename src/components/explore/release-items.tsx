"use client";
/* eslint-disable @next/next/no-img-element -- set art comes from the pricing source's CDN */

import { Bell, BellRing } from "lucide-react";
import Link from "next/link";
import { toast } from "sonner";
import type { ExploreSet } from "@/lib/explore/types";
import { daysUntil, useReleaseReminders, whenLabel } from "@/lib/reminders";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

export function ReminderButton({ set, compact }: { set: ExploreSet; compact?: boolean }) {
  const { has, toggle } = useReleaseReminders();
  const on = has(set.slug);
  return (
    <button
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        const now = toggle(set.slug);
        toast(now ? `We'll remind you about ${set.name}` : `Reminder removed for ${set.name}`);
      }}
      aria-pressed={on}
      aria-label={on ? `Remove reminder for ${set.name}` : `Remind me about ${set.name}`}
      className={cn(
        "inline-flex shrink-0 items-center gap-1.5 rounded-full text-[12px] font-medium transition-colors",
        compact ? "size-8 justify-center" : "h-8 px-3",
        on ? "bg-accent text-accent-foreground" : "bg-surface-2 text-muted hover:text-foreground",
      )}
    >
      {on ? <BellRing className="size-3.5" /> : <Bell className="size-3.5" />}
      {!compact && (on ? "Reminding" : "Remind me")}
    </button>
  );
}

/** One upcoming (or just-released) set as a calendar row. */
export function ReleaseRow({ set }: { set: ExploreSet }) {
  const { today } = useStore();
  const days = set.releaseDate ? daysUntil(set.releaseDate, today) : null;
  const d = set.releaseDate ? new Date(`${set.releaseDate}T00:00:00Z`) : null;
  const body = (
    <>
      <div className="flex w-12 shrink-0 flex-col items-center rounded-xl bg-surface-2 py-1.5">
        <span className="text-[10px] font-semibold uppercase tracking-wider text-subtle">{d?.toLocaleString("en-US", { month: "short", timeZone: "UTC" })}</span>
        <span className="tabular text-[18px] font-semibold leading-tight">{d?.getUTCDate()}</span>
      </div>
      <div className="hidden h-12 w-[72px] shrink-0 overflow-hidden rounded-lg bg-image-well sm:block">
        {set.iconUrl ? <img src={set.iconUrl} alt="" loading="lazy" className="h-full w-full object-cover" /> : set.imageUrl ? <img src={set.imageUrl} alt="" loading="lazy" className="h-full w-full object-contain p-1" /> : null}
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-[14px] font-medium">{set.name}</p>
        <p className="truncate text-[12px] text-muted">
          {set.gameName}
          {days !== null && <span className={cn(days >= 0 && days <= 7 && "text-foreground")}> · {whenLabel(days)}</span>}
        </p>
      </div>
      {days !== null && days >= 0 && <ReminderButton set={set} />}
    </>
  );
  const cls = "flex items-center gap-3 rounded-2xl px-2 py-2.5 transition-colors sm:gap-4";
  return set.loaded ? (
    <Link href={`/explore/${encodeURIComponent(set.slug)}`} className={cn(cls, "hover:bg-surface-2/60")}>
      {body}
    </Link>
  ) : (
    <div className={cls}>{body}</div>
  );
}
