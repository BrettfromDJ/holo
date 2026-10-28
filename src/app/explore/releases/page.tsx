"use client";

import { CalendarDays, ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { useExploreIndex } from "@/components/explore/explore-items";
import { ReleaseRow } from "@/components/explore/release-items";
import { Skeleton } from "@/components/ui/skeleton";
import { addDays } from "@/lib/finance/dates";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

/** Upcoming sets across every brand, by month, plus the last 30 days of releases. */
export default function ReleaseCalendarPage() {
  const index = useExploreIndex();
  const { today } = useStore();
  const [brand, setBrand] = useState<string>("all");

  const { upcoming, recent, brands } = useMemo(() => {
    if (index.status !== "ready") return { upcoming: [], recent: [], brands: [] };
    const sets = index.sets.filter((s) => s.releaseDate && (brand === "all" || s.gameSlug === brand));
    const up = sets.filter((s) => s.releaseDate! >= today).sort((a, b) => (a.releaseDate! < b.releaseDate! ? -1 : 1));
    const months = new Map<string, typeof up>();
    for (const s of up) {
      const m = s.releaseDate!.slice(0, 7);
      months.set(m, [...(months.get(m) ?? []), s]);
    }
    const since = addDays(today, -30);
    return {
      upcoming: [...months.entries()],
      recent: sets.filter((s) => s.releaseDate! < today && s.releaseDate! >= since).sort((a, b) => (a.releaseDate! > b.releaseDate! ? -1 : 1)),
      brands: index.games.filter((g) => index.sets.some((s) => s.gameSlug === g.slug && s.releaseDate && s.releaseDate >= since)),
    };
  }, [index, brand, today]);

  return (
    <div className="animate-fade-in">
      <Link href="/explore" className="mb-6 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
        <ChevronLeft className="size-4" /> Explore
      </Link>
      <h1 className="text-[28px] font-semibold tracking-[-0.02em] sm:text-[34px]">Release calendar</h1>
      <p className="mt-1 text-[14px] text-muted">Upcoming sets across every brand. Tap the bell to get a reminder on your Overview.</p>

      {brands.length > 1 && (
        <div className="scrollbar-none -mx-1 mt-5 flex gap-1.5 overflow-x-auto px-1">
          {[{ slug: "all", name: "All brands" }, ...brands].map((b) => (
            <button
              key={b.slug}
              onClick={() => setBrand(b.slug)}
              aria-pressed={brand === b.slug}
              className={cn("h-8 shrink-0 rounded-full px-3.5 text-[13px] font-medium transition-colors", brand === b.slug ? "bg-lime font-semibold text-[#0b0b0c] shadow-[0_0_16px_-4px_var(--lime)]" : "bg-surface-2 text-muted hover:text-foreground")}
            >
              {b.name}
            </button>
          ))}
        </div>
      )}

      {index.status === "loading" ? (
        <div className="mt-8 space-y-3">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-16 w-full rounded-2xl" />
          ))}
        </div>
      ) : index.status === "error" ? (
        <p className="py-20 text-center text-[14px] text-muted">{index.message}</p>
      ) : (
        <>
          {upcoming.length ? (
            upcoming.map(([month, sets]) => (
              <section key={month} className="mt-8" aria-label={month}>
                <h2 className="mb-2 border-b border-border pb-2 text-[18px] font-semibold">
                  {new Date(`${month}-01T00:00:00Z`).toLocaleString("en-US", { month: "long", year: "numeric", timeZone: "UTC" })}
                </h2>
                {sets.map((s) => (
                  <ReleaseRow key={s.slug} set={s} />
                ))}
              </section>
            ))
          ) : (
            <div className="flex flex-col items-center py-16 text-center">
              <CalendarDays className="size-9 text-subtle" strokeWidth={1.5} />
              <p className="mt-3 font-medium">No announced releases yet</p>
              <p className="mt-1 max-w-sm text-sm text-muted">New sets appear here as soon as they&apos;re listed in the catalog (the set list refreshes weekly).</p>
            </div>
          )}

          {recent.length > 0 && (
            <section className="mt-12" aria-label="Recently released">
              <h2 className="mb-2 border-b border-border pb-2 text-[18px] font-semibold">Released in the last 30 days</h2>
              {recent.map((s) => (
                <ReleaseRow key={s.slug} set={s} />
              ))}
            </section>
          )}
        </>
      )}
    </div>
  );
}
