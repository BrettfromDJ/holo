"use client";

import { useMemo } from "react";
import { RecentTimeline } from "@/components/overview/boards";
import { ActivityBars, ActivityBinder, ActivityCalendar, ActivityDeck, ActivityFilmstrip, ActivityHand, ActivityPeriods, ActivityReceipt, ActivitySince, ActivityTicker } from "@/components/overview/activity-prototypes";
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
    { id: "6", name: "Binder page", note: "Pockets with a plastic sheen, price stickers, and an empty pocket to add the next one.", el: <ActivityBinder holdings={recent} /> },
    { id: "7", name: "Hand", note: "Held like a hand of cards; hover one to pull it up and read it.", el: <ActivityHand holdings={recent} /> },
    { id: "8", name: "Paid vs worth", note: "Two faint bars each, what you paid against what it's worth; the number carries the color.", el: <ActivityBars holdings={recent} /> },
    { id: "9", name: "By period", note: "This week, this month and earlier, each with what went in and how it's doing.", el: <ActivityPeriods holdings={recent} /> },
    { id: "10", name: "Since you bought", note: "Each add's price since the day you bought it, against a dashed line at what you paid.", el: <ActivitySince holdings={recent} /> },
    { id: "0", name: "Current", note: "Today's timeline, for comparison.", el: <RecentTimeline holdings={recent} /> },
  ];
  return (
    <div>
      <PageHeader title="Activity box lab" subtitle="Ten prototypes of the Recently added box on Overview, using your collection" />
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
