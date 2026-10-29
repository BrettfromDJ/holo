"use client";

import { useMemo } from "react";
import { RecentTimeline } from "@/components/overview/boards";
import { ActivityCalendar, ActivityDeck, ActivityFilmstrip, ActivityReceipt, ActivityTicker } from "@/components/overview/activity-prototypes";
import { PageHeader } from "@/components/shell/page-header";
import { usePortfolio } from "@/lib/store/collection-store";

/** Prototype page: five takes on the Overview "Recently added" box, next to the current one. */
export default function ActivityLabPage() {
  const { holdings } = usePortfolio();
  const recent = useMemo(() => [...holdings].sort((a, b) => ((b.lastAcquired ?? "") > (a.lastAcquired ?? "") ? 1 : -1)).slice(0, 5), [holdings]);
  const versions = [
    { id: "1", name: "Filmstrip", note: "Big card art in a row, date and return on each.", el: <ActivityFilmstrip holdings={recent} /> },
    { id: "2", name: "Receipt", note: "A printed receipt with what you paid, what it's worth now, and the difference.", el: <ActivityReceipt holdings={recent} /> },
    { id: "3", name: "Calendar", note: "Six months of buying as a heat grid, latest adds beside it.", el: <ActivityCalendar holdings={recent} /> },
    { id: "4", name: "Ticker", note: "Huge display-type rows; hover one to float its card in.", el: <ActivityTicker holdings={recent} /> },
    { id: "5", name: "Deck", note: "Newest piece featured with its story; tap a thumbnail to swap.", el: <ActivityDeck holdings={recent} /> },
    { id: "0", name: "Current", note: "Today's timeline, for comparison.", el: <RecentTimeline holdings={recent} /> },
  ];
  return (
    <div>
      <PageHeader title="Activity box lab" subtitle="Five prototypes of the Recently added box on Overview, using your collection" />
      <div className="space-y-16">
        {versions.map((v) => (
          <section key={v.id}>
            <p className="mb-4 flex items-baseline gap-3">
              <span className="tag-skew tag-lime">{v.id === "0" ? "Now" : `V${v.id}`}</span>
              <span className="font-display text-[20px] uppercase tracking-[0.01em]">{v.name}</span>
              <span className="text-[13px] text-muted">{v.note}</span>
            </p>
            {v.el}
          </section>
        ))}
      </div>
    </div>
  );
}
