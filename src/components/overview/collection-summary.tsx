"use client";

import { useEffect, useMemo } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Reveal } from "@/components/motion/reveal";
import { RecentTimeline } from "@/components/overview/boards";
import { BudgetCard } from "@/components/overview/budget-card";
import { HypeHeading, HypeHero } from "@/components/overview/hype-hero";
import { ReleaseReminders } from "@/components/overview/release-reminders";
import { Shelf, Spotlight } from "@/components/overview/sections";
import { EmptyPage } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { PerformanceChart } from "@/components/portfolio/performance-chart";
import { PortfolioPill } from "@/components/portfolio/portfolio-controls";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { formatDate, money, relativeTime } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";

/**
 * Collection's Summary (what Overview was; the app's `HomeView`): the worth, the chart, the
 * budget, the star of the collection, the most valuable shelf and what you added lately.
 * No ticker, metric cards, movers or category plans (the owner's alignment with the app).
 */
export function CollectionSummary({ onViewCards }: { onViewCards: () => void }) {
  const store = useStore();
  const { holdings, summary, timeline } = usePortfolio();
  const recent = useMemo(() => [...holdings].sort((a, b) => ((b.lastAcquired ?? "") > (a.lastAcquired ?? "") ? 1 : -1)).slice(0, 5), [holdings]);

  if (store.status === "loading") return <SummarySkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) {
    return <EmptyPage title="Nothing here yet" line="Scan a card to see what it's worth." action="Search cards" href="/search" link="Browse Explore" linkHref="/explore" />;
  }

  return (
    <div className="animate-fade-in">
      <HypeHero holdings={holdings} summary={summary} onViewCards={onViewCards} above={<PortfolioPill className="mb-3" />} />
      <ReleaseReminders />

      <div className="mt-6">
        <PerformanceChart
          timeline={timeline}
          header={(scrub) => (
            <div className="mb-3">
              <HypeHeading title="Performance" action={store.mode === "demo" ? <Badge variant="sample">Sample data</Badge> : undefined} />
              {/* The hero already shows today's value; here it follows the scrubbed day. */}
              <p className="tabular -mt-2 text-[13px] text-muted">
                {scrub ? (
                  <>
                    {formatDate(scrub.date)} · <span className="font-semibold text-foreground">{money(scrub.value)}</span>
                  </>
                ) : (
                  "Drag across the chart to see any day"
                )}
              </p>
            </div>
          )}
        />
      </div>

      <div className="mt-8">
        <BudgetCard />
        <PriceFreshness />
      </div>

      <div className="mt-14 space-y-14">
        <Reveal>
          <Spotlight holdings={holdings} />
        </Reveal>
        <Reveal>
          <Shelf holdings={holdings} title="Most valuable" onSeeAll={onViewCards} />
        </Reveal>
        <Reveal>
          <RecentTimeline holdings={recent} />
        </Reveal>
      </div>
    </div>
  );
}

/** Where the prices come from, as one quiet line (no Refresh button: the daily sync keeps them fresh). */
function PriceFreshness() {
  const { mode, integrations, pricesRefreshedAt, priceError } = useStore();
  if (mode === "demo") return <p className="mt-3 text-[12px] text-subtle">Sample prices are generated for demonstration and are not market data.</p>;
  return (
    <p className="mt-3 text-[12px] text-subtle">
      {integrations.tcgapi ? `Prices from TCG API · refreshed ${relativeTime(pricesRefreshedAt)} · updates daily` : "Live pricing isn't configured — showing last stored prices."}
      {priceError && <span className="ml-2 text-down">{priceError}</span>}
    </p>
  );
}

function SummarySkeleton() {
  return (
    <div aria-busy="true" aria-label="Loading your collection" className="flex flex-col items-center lg:items-start">
      <Skeleton className="mt-6 h-6 w-56" />
      <Skeleton className="mt-3 h-12 w-64" />
      <Skeleton className="mt-5 h-14 w-full max-w-[460px] rounded-[20px]" />
      <Skeleton className="mt-8 h-[280px] w-full rounded-3xl" />
    </div>
  );
}

/**
 * Opens Your week from the menu ("?week=1"), and on its own once a week: the first visit on or
 * after Sunday. Remembered in this browser per account (`recap-seen:<user id>`, the start of the
 * last week shown). The first time ever it only marks this week, then waits for Sunday. Not in
 * the demo. Same rule as the app.
 */
export function RecapOpener({ onOpen }: { onOpen: () => void }) {
  const params = useSearchParams();
  const router = useRouter();
  const store = useStore();
  const fromMenu = params.get("week") === "1";
  const userId = store.mode === "personal" ? (store.user?.id ?? null) : null;
  const hasHoldings = store.status === "ready" && store.data.transactions.length > 0;

  useEffect(() => {
    if (!fromMenu) return;
    onOpen();
    router.replace("/collection?view=summary", { scroll: false });
  }, [fromMenu, onOpen, router]);

  useEffect(() => {
    if (!userId || !hasHoldings) return;
    const now = new Date();
    const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay()).getTime();
    const key = `recap-seen:${userId}`;
    let seen: number | null = null;
    try {
      const raw = localStorage.getItem(key);
      seen = raw ? Number(raw) : null;
      localStorage.setItem(key, String(weekStart));
    } catch {
      return;
    }
    if (seen !== null && seen < weekStart) onOpen();
  }, [userId, hasHoldings, onOpen]);

  return null;
}
