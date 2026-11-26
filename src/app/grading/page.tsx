"use client";

import { MoreHorizontal, Send, SlidersHorizontal } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { loadSummaries, summaryFor } from "@/lib/ebay-client";
import type { EbaySummary } from "@/lib/ebay-types";
import { toast } from "sonner";
import { formatSent, GradeChip, GradingCostsDialog, ReturnDialog, SendToGraderDialog, slabSourceLabel, useAtGrader } from "@/components/grading/grading-items";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { ProductImage } from "@/components/product/product-image";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { PageHeader, type HeaderStat } from "@/components/shell/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, SectionTitle } from "@/components/ui/card";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { daysBetween } from "@/lib/finance/dates";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, moneyWhole, signedMoney } from "@/lib/format";
import { gradedSalesFrom, gradedSampleFor, gradeLabel, gradingOutlook, isStaleValue, liquidityLabel, sampleSalesPerYear } from "@/lib/graded";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useGradingCosts, useGradingSubmissions, type GradingSubmission } from "@/lib/store/grading";
import { holdingKey, priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";

type Outlook = ReturnType<typeof gradingOutlook>;

/** Raw cards below this price rarely cover the cost of grading. */
const MIN_RAW = 15;
const CANDIDATES = 8;

export default function GradingPage() {
  const store = useStore();
  const { holdings } = usePortfolio();
  const { costs } = useGradingCosts();
  const { submissions } = useGradingSubmissions();
  const atGrader = useAtGrader();
  const [costsOpen, setCostsOpen] = useState(false);
  const [showAll, setShowAll] = useState(false);

  const slabs = useMemo(() => holdings.filter((h) => h.identity.grade).sort((a, b) => (b.value ?? 0) - (a.value ?? 0)), [holdings]);

  // Real cards (raw candidates and slabs) get eBay figures in one bulk request.
  const realIds = useMemo(() => [...new Set(holdings.filter((h) => h.product?.kind === "single" && !gradedSampleFor(h.identity.productId)).map((h) => h.identity.productId))].sort(), [holdings]);
  const [summaries, setSummaries] = useState<Record<string, EbaySummary[]>>({});
  useEffect(() => {
    if (!realIds.length) return;
    let cancelled = false;
    loadSummaries(realIds)
      .then((m) => !cancelled && setSummaries(m))
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [realIds]);
  const summaryOf = (h: HoldingView) => (gradedSampleFor(h.identity.productId) ? null : summaryFor(summaries[h.identity.productId], h.identity.printing));

  const candidates = useMemo(() => {
    const out: { h: HoldingView; outlook: Outlook }[] = [];
    for (const h of holdings) {
      if (h.identity.grade || h.product?.kind !== "single" || h.price === null || h.price < MIN_RAW) continue;
      const loaded = h.identity.productId in summaries;
      const sales = loaded ? (gradedSalesFrom(summaryFor(summaries[h.identity.productId], h.identity.printing)) ?? { psa10: null, psa9: null, psa10Count: 0 }) : null;
      out.push({
        h,
        outlook: gradingOutlook(h.identity.productId, h.price, costs, gradedSampleFor(h.identity.productId) ? null : sales),
      });
    }
    // Biggest PSA 10 upside first, so the list reads in order of the figure it shows (like the app).
    return out.filter((c) => c.outlook.upside10 > 0).sort((a, b) => b.outlook.upside10 - a.outlook.upside10);
  }, [holdings, costs, summaries]);

  if (store.status === "loading") return <Skeleton className="h-[600px] w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) {
    return (
      <>
        <PageHeader title="Grading" />
        <EmptyCollection title="Nothing to grade yet" />
      </>
    );
  }

  const sent = submissions.filter((s) => s.status === "sent").sort((a, b) => (a.sentOn < b.sentOn ? -1 : 1));
  const returned = submissions
    .filter((s) => s.status === "returned")
    .sort((a, b) => ((a.returnedOn ?? "") < (b.returnedOn ?? "") ? 1 : -1))
    .slice(0, 5);
  const slabValue = slabs.reduce((s, h) => s + (h.value ?? 0), 0);
  const rawEquivalent = slabs.reduce((s, h) => {
    const raw = store.data.prices[priceKey(h.identity.productId, h.identity.printing)]?.market;
    return raw == null || h.value === null ? s : s + raw * h.quantity;
  }, 0);
  const stale = slabs.filter((h) => h.priceOrigin === "manual" && isStaleValue(h.priceUpdatedAt, store.today)).length;
  const sentCount = sent.reduce((s, x) => s + x.quantity, 0);
  const slabCount = slabs.reduce((s, h) => s + h.quantity, 0);

  const premium = slabValue - rawEquivalent;
  const costsButton = (
    <Button variant="ghost" size="icon" aria-label="Grading costs" onClick={() => setCostsOpen(true)}>
      <SlidersHorizontal />
    </Button>
  );
  // Only numbers that say something: no "0 at grader" or "0 to refresh". Same as the app.
  const stats: HeaderStat[] = [
    {
      label: "Premium",
      value: rawEquivalent > 0 ? signedMoney(premium) : "—",
      tone: rawEquivalent > 0 ? (premium >= 0 ? "up" : "down") : undefined,
    },
    {
      label: "Raw, they'd be",
      value: rawEquivalent > 0 ? money(rawEquivalent) : "—",
    },
    ...(sentCount > 0 ? [{ label: "At grader", value: String(sentCount) }] : stale > 0 ? [{ label: "To refresh", value: String(stale) }] : []),
  ];

  return (
    <div className="animate-fade-in">
      <PortfolioSwitcher compact className="mb-4 lg:hidden" />
      <PortfolioBanner />
      {/* Only what has something in it: no $0.00 hero, no empty slabs or empty grader panel. */}
      {slabs.length ? (
        <div className="relative">
          <PageHeader
            title="Your slabs are worth"
            figure={<AnimatedNumber value={slabValue} format={money} duration={1300} from={slabValue * 0.85} />}
            note={
              <span className="flex flex-wrap items-center gap-2">
                <span className="tabular rounded-md bg-lime px-2 py-0.5 text-[13px] font-semibold text-[#0b0b0c]">
                  {slabCount} slab{slabCount === 1 ? "" : "s"}
                </span>
                {rawEquivalent > 0 && <span>{(slabValue / rawEquivalent).toFixed(1)}× what they&apos;re worth raw</span>}
              </span>
            }
            actions={slabs.some((h) => gradedSampleFor(h.identity.productId)) ? <Badge variant="sample">Sample graded prices</Badge> : undefined}
            stats={stats}
          />
          {/* The grading costs behind a quiet icon at the top right, like the app's toolbar. */}
          <div className="absolute -top-2 right-0">{costsButton}</div>
        </div>
      ) : (
        <PageHeader title="Grading" actions={costsButton} />
      )}

      <div className="max-w-[760px] space-y-10">
        {(sent.length > 0 || returned.length > 0) && (
          <Card className="p-5 sm:p-6">
            <SectionTitle title="At the grader" subtitle="Cards stay raw until they come back" />
            {sent.length > 0 && (
              <ul className="divide-y divide-border">
                {sent.map((s) => (
                  <SubmissionRow key={s.id} s={s} />
                ))}
              </ul>
            )}
            {returned.length > 0 && (
              <div className={cn(sent.length > 0 && "mt-5 border-t border-border pt-4")}>
                <p className="mb-2 font-mono text-[11px] font-medium uppercase tracking-[0.06em] text-subtle">Recently returned</p>
                <ul className="space-y-1.5">
                  {returned.map((s) => (
                    <li key={s.id} className="flex items-center gap-2 text-[13px]">
                      <GradeChip grade={{ company: s.company, grade: s.grade ?? "?" }} />
                      <Link href={`/product/${encodeURIComponent(s.productId)}`} className="min-w-0 flex-1 truncate hover:underline">
                        {store.data.products[s.productId]?.name ?? "Card"}
                      </Link>
                      <span className="shrink-0 text-[12px] text-subtle">{s.returnedOn ? formatDate(s.returnedOn) : ""}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </Card>
        )}

        <section>
          <SectionTitle title="Worth grading" subtitle={`What each could make as a PSA 10, after ${moneyWhole(costs.fee + costs.shipping)} to grade and ship.`} className="mb-2" />
          {candidates.length ? (
            // Plain rows on the page (no panel), divided by a hairline.
            <ul className="divide-y divide-foreground/[0.08]">
              {(showAll ? candidates : candidates.slice(0, CANDIDATES)).map(({ h, outlook }) => (
                <CandidateRow key={h.key} h={h} outlook={outlook} sent={(atGrader.get(h.key) ?? 0) >= h.quantity} onCosts={() => setCostsOpen(true)} />
              ))}
            </ul>
          ) : (
            <p className="py-3 text-[13px] text-muted">No raw singles worth more than {moneyWhole(MIN_RAW)} with upside after grading&nbsp;costs.</p>
          )}
          {candidates.length > CANDIDATES && (
            <button type="button" onClick={() => setShowAll((v) => !v)} className="mt-1 text-[14px] font-medium text-muted hover:text-foreground">
              {showAll ? "Show fewer" : `Show all ${candidates.length}`}
            </button>
          )}
        </section>
      </div>

      {slabs.length > 0 && (
        <section className="mt-10">
          <SectionTitle title="Your slabs" subtitle="Graded cards, by value" />
          <div className="grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-5">
            {slabs.map((h) => (
              <SlabTile key={h.key} h={h} today={store.today} summary={summaryOf(h)} />
            ))}
          </div>
        </section>
      )}

      <GradingCostsDialog open={costsOpen} onOpenChange={setCostsOpen} />
    </div>
  );
}

function SubmissionRow({ s }: { s: GradingSubmission }) {
  const { data, today } = useStore();
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const { cancel } = useGradingSubmissions();
  const [open, setOpen] = useState(false);
  const product = data.products[s.productId];
  const holding = holdings.find(
    (h) =>
      h.key ===
      holdingKey({
        productId: s.productId,
        printing: s.printing,
        condition: s.condition,
        grade: null,
      }),
  );
  return (
    <li className="flex items-center gap-3 py-3">
      <ProductImage product={product} size="xs" className="size-11 shrink-0 rounded-lg" />
      <div className="min-w-0 flex-1">
        <Link href={`/product/${encodeURIComponent(s.productId)}`} className="block truncate text-[14px] font-medium hover:underline">
          {s.quantity > 1 && <span className="text-muted">{s.quantity} × </span>}
          {product?.name ?? "Card"}
        </Link>
        <p className="truncate text-[12px] text-muted">{formatSent(s, today)}</p>
      </div>
      <Button size="sm" variant="secondary" onClick={() => setOpen(true)}>
        It&apos;s back
      </Button>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon-sm" aria-label="Submission actions">
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem
            onSelect={() => {
              cancel(s.id);
              toast.success("Submission removed");
            }}
          >
            Remove submission
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <ReturnDialog submission={s} holding={holding} open={open} onOpenChange={setOpen} />
    </li>
  );
}

/** "+$25,099" / "−$40": whole dollars with a sign. */
const signedWhole = (v: number) => `${v < 0 ? "−" : "+"}${moneyWhole(Math.abs(v))}`;

/** The row's quiet line: sent, or what a 9 makes and how 10s sell ("+$1,024 at a 9 · 10s sell steadily"). */
function detailLine(o: Outlook, sent: boolean) {
  if (sent) return "At the grader";
  const nine = `${signedWhole(o.upside9)} at a 9`;
  if (o.source !== "sales") return `${nine} · estimate`;
  return `${nine} · ${o.psa10Sales >= 52 ? "10s sell fast" : o.psa10Sales >= 12 ? "10s sell steadily" : "10s sell slowly"}`;
}

/** Picture | name, raw → PSA 10, one quiet line | the upside, then ⋯ (Send for grading, Grading costs). */
function CandidateRow({ h, outlook: o, sent, onCosts }: { h: HoldingView; outlook: Outlook; sent: boolean; onCosts: () => void }) {
  const [open, setOpen] = useState(false);
  const est = o.source === "estimate" ? "≈" : "";
  return (
    <li className="flex items-center gap-1 py-3">
      <Link href={`/product/${encodeURIComponent(h.identity.productId)}`} className="group flex min-w-0 flex-1 items-center gap-3">
        <ProductImage product={h.product} size="xs" frame={false} className="h-14 w-10 shrink-0 overflow-hidden rounded-[3px]" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[15px] font-medium group-hover:underline">{h.product?.name ?? "Card"}</p>
          <p className="tabular mt-0.5 truncate text-[12px] text-muted">
            {moneyWhole(o.raw)} raw → {est}
            {moneyWhole(o.psa10)} PSA 10
          </p>
          <p className="tabular mt-0.5 truncate text-[12px] text-subtle">{detailLine(o, sent)}</p>
        </div>
        <span className="tabular shrink-0 pl-2 text-[16px] font-semibold text-up">{signedWhole(o.upside10)}</span>
      </Link>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon-sm" aria-label={`Actions for ${h.product?.name ?? "card"}`} className="-mr-2 text-muted">
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem disabled={sent} onSelect={() => setOpen(true)}>
            <Send /> {sent ? "Sent for grading" : "Send for grading"}
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={onCosts}>
            <SlidersHorizontal /> Grading costs
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <SendToGraderDialog holding={h} open={open} onOpenChange={setOpen} />
    </li>
  );
}

function SlabTile({ h, today, summary }: { h: HoldingView; today: string; summary: EbaySummary | null }) {
  const { data } = useStore();
  const raw = data.prices[priceKey(h.identity.productId, h.identity.printing)]?.market ?? null;
  const manual = h.priceOrigin === "manual";
  const stale = manual && isStaleValue(h.priceUpdatedAt, today);
  return (
    <Link href={`/product/${encodeURIComponent(h.identity.productId)}`} className="group flex min-w-0 flex-col">
      <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} size="md" className="aspect-[4/5] w-full transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1" />
      <p className="mt-3 line-clamp-2 text-[13px] font-medium leading-snug">{h.product?.name ?? "Card"}</p>
      <p className="tabular mt-1 text-[14px] font-semibold">
        {h.price === null ? <span className="text-subtle">No value</span> : money(h.value)}
        {raw !== null && h.price !== null && <span className="ml-1.5 font-mono text-[11px] font-normal text-muted">{(h.price / raw).toFixed(1)}× raw</span>}
      </p>
      <p className={cn("text-[11px]", stale ? "text-foreground/80" : "text-subtle")}>{manual ? (stale ? `Your value · ${daysBetween(h.priceUpdatedAt!, today)} days old` : "Your value") : slabSourceLabel(h)}</p>
      {raw !== null && h.identity.grade && (
        <p className="text-[11px] text-subtle">{liquidityLabel(summary ? (summary.graded[gradeLabel(h.identity.grade)]?.count ?? 0) * 12 : sampleSalesPerYear(h.identity.productId, h.identity.grade, raw))}</p>
      )}
    </Link>
  );
}
