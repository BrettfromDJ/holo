"use client";

import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useMemo } from "react";
import { useExploreIndex } from "@/components/explore/explore-items";
import { ExploreBackdrop, NextRelease } from "@/components/explore/landing";
import { CalendarRow } from "@/components/explore/release-items";
import { Skeleton } from "@/components/ui/skeleton";
import { addDays } from "@/lib/finance/dates";
import { useReleaseReminders } from "@/lib/reminders";
import { useStore } from "@/lib/store/collection-store";
import type { ExploreSet } from "@/lib/explore/types";
import { cn } from "@/lib/utils";

/** Upcoming sets across every game by month, plus the last 30 days of releases (the app's ReleaseCalendarView). */
export default function ReleaseCalendarPage() {
  const index = useExploreIndex();
  const { today } = useStore();
  const reminders = useReleaseReminders();

  const { upcoming, months, recent, soon } = useMemo(() => {
    if (index.status !== "ready") return { upcoming: [], months: [], recent: [], soon: 0 };
    const sets = index.sets.filter((s) => s.releaseDate);
    const up = sets.filter((s) => s.releaseDate! >= today).sort((a, b) => (a.releaseDate! < b.releaseDate! ? -1 : 1));
    const months = new Map<string, ExploreSet[]>();
    for (const s of up) {
      const m = s.releaseDate!.slice(0, 7);
      months.set(m, [...(months.get(m) ?? []), s]);
    }
    const since = addDays(today, -30);
    const in30 = addDays(today, 30);
    return {
      upcoming: up,
      months: [...months.entries()],
      recent: sets.filter((s) => s.releaseDate! < today && s.releaseDate! >= since).sort((a, b) => (a.releaseDate! > b.releaseDate! ? -1 : 1)),
      soon: up.filter((s) => s.releaseDate! <= in30).length,
    };
  }, [index, today]);
  const reminded = upcoming.filter((s) => reminders.has(s.slug)).length;

  return (
    <div className="relative animate-fade-in">
      <ExploreBackdrop />
      <Link href="/explore" className="mb-5 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
        <ChevronLeft className="size-4" /> Explore
      </Link>
      <h1 className="font-display text-[30px] leading-[1.02] tracking-[-0.035em] sm:text-[34px]">Release calendar</h1>
      <p className="mt-2 text-[14px] text-muted">Tap the bell to get a reminder on your Home.</p>

      {index.status === "loading" ? (
        <div className="mt-6 space-y-3">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-[80px] w-full rounded-[18px]" />
          ))}
        </div>
      ) : index.status === "error" ? (
        <p className="py-20 text-center text-[14px] text-muted">{index.message}</p>
      ) : (
        <>
          <div className="mt-6 grid grid-cols-3 gap-2 sm:max-w-xl">
            <StatTile label="Upcoming" value={upcoming.length} />
            <StatTile label="Next 30 days" value={soon} />
            <StatTile label="Reminders" value={reminded} lime />
          </div>
          {upcoming[0] && (
            <div className="mt-5">
              <NextRelease set={upcoming[0]} />
            </div>
          )}

          {upcoming.length === 0 && <p className="mt-9 text-[14px] text-muted">No upcoming releases in the catalog&nbsp;yet.</p>}
          {months.map(([month, sets]) => (
            <Section key={month} title={new Date(`${month}-01T00:00:00Z`).toLocaleString("en-US", { month: "long", year: "numeric", timeZone: "UTC" })} sets={sets} upcoming />
          ))}
          {recent.length > 0 && <Section title="Out in the last 30 days" sets={recent} upcoming={false} />}
        </>
      )}
    </div>
  );
}

function Section({ title, sets, upcoming }: { title: string; sets: ExploreSet[]; upcoming: boolean }) {
  return (
    <section className="mt-9" aria-label={title}>
      <div className="mb-3 flex items-baseline gap-2.5">
        <h2 className="font-display text-[24px] leading-none tracking-[-0.03em]">{title}</h2>
        <span className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">
          {sets.length} set{sets.length === 1 ? "" : "s"}
        </span>
      </div>
      <div className="grid gap-2.5 lg:grid-cols-2">
        {sets.map((s) => (
          <CalendarRow key={s.slug} set={s} upcoming={upcoming} />
        ))}
      </div>
    </section>
  );
}

/** A glass tile with a mono label and a big number (the app's StatTile). */
function StatTile({ label, value, lime }: { label: string; value: number; lime?: boolean }) {
  return (
    <div className="glass rounded-2xl px-3.5 py-3">
      <p className="truncate font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{label}</p>
      <p className={cn("tabular mt-1 font-display text-[28px] leading-none tracking-[-0.035em]", lime ? "text-[var(--lime)]" : "text-white")}>{value.toLocaleString()}</p>
    </div>
  );
}
