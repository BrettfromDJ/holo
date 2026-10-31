"use client";

import { MoreHorizontal, Send } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { loadSummaries, summaryFor } from "@/lib/ebay-client";
import type { EbaySummary } from "@/lib/ebay-types";
import { toast } from "sonner";
import { Field, MoneyInput, parseMoney } from "@/components/flows/fields";
import { FormShell } from "@/components/flows/transaction-dialogs";
import { formatSent, GradeChip, ReturnDialog, SendToGraderDialog, slabSourceLabel, useAtGrader } from "@/components/grading/grading-items";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { ProductImage } from "@/components/product/product-image";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { PageHeader } from "@/components/shell/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, SectionTitle } from "@/components/ui/card";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { daysBetween } from "@/lib/finance/dates";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, signedMoney } from "@/lib/format";
import { gradedSalesFrom, gradedSampleFor, gradeLabel, gradingOutlook, isStaleValue, liquidityLabel, liquidityOf, sampleSalesPerYear } from "@/lib/graded";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useGradingCosts, useGradingSubmissions, type GradingSubmission } from "@/lib/store/grading";
import { holdingKey, priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";

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
  const realIds = useMemo(
    () => [...new Set(holdings.filter((h) => h.product?.kind === "single" && !gradedSampleFor(h.identity.productId)).map((h) => h.identity.productId))].sort(),
    [holdings],
  );
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
    const out: { h: HoldingView; outlook: ReturnType<typeof gradingOutlook> }[] = [];
    for (const h of holdings) {
      if (h.identity.grade || h.product?.kind !== "single" || h.price === null || h.price < MIN_RAW) continue;
      const loaded = h.identity.productId in summaries;
      const sales = loaded ? gradedSalesFrom(summaryFor(summaries[h.identity.productId], h.identity.printing)) ?? { psa10: null, psa9: null, psa10Count: 0 } : null;
      out.push({ h, outlook: gradingOutlook(h.identity.productId, h.price, costs, gradedSampleFor(h.identity.productId) ? null : sales) });
    }
    // Ranked by upside, discounted when PSA 10s of the card rarely sell.
    return out.filter((c) => c.outlook.upside10 > 0).sort((a, b) => b.outlook.score - a.outlook.score);
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
  const returned = submissions.filter((s) => s.status === "returned").sort((a, b) => ((a.returnedOn ?? "") < (b.returnedOn ?? "") ? 1 : -1)).slice(0, 5);
  const slabValue = slabs.reduce((s, h) => s + (h.value ?? 0), 0);
  const rawEquivalent = slabs.reduce((s, h) => {
    const raw = store.data.prices[priceKey(h.identity.productId, h.identity.printing)]?.market;
    return raw == null || h.value === null ? s : s + raw * h.quantity;
  }, 0);
  const stale = slabs.filter((h) => h.priceOrigin === "manual" && isStaleValue(h.priceUpdatedAt, store.today)).length;
  const sentCount = sent.reduce((s, x) => s + x.quantity, 0);
  const slabCount = slabs.reduce((s, h) => s + h.quantity, 0);

  return (
    <div className="animate-fade-in">
      <PortfolioSwitcher compact className="mb-4 lg:hidden" />
      <PortfolioBanner />
      {/* Like the app: the slabs' worth up top, how many and their premium over raw, then the
          grader and refresh counts. */}
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
        stats={[
          { label: "Premium", value: rawEquivalent > 0 ? signedMoney(slabValue - rawEquivalent) : "—", tone: rawEquivalent > 0 ? (slabValue - rawEquivalent >= 0 ? "up" : "down") : undefined },
          { label: "At grader", value: String(sentCount) },
          { label: "To refresh", value: String(stale) },
        ]}
      />

      <div className="grid grid-cols-1 items-start gap-6 xl:grid-cols-2">
        <Card className="p-5 sm:p-6">
          <SectionTitle title="At the grader" subtitle="Cards stay raw until they come back" />
          {sent.length ? (
            <ul className="divide-y divide-border">
              {sent.map((s) => (
                <SubmissionRow key={s.id} s={s} />
              ))}
            </ul>
          ) : (
            // Short and left-aligned, so the empty card stays compact instead of a tall box with a wrapped sentence.
            <div className="flex items-center gap-3 rounded-2xl bg-surface-2/60 px-4 py-3.5">
              <Send className="size-4 shrink-0 text-subtle" />
              <p className="text-[13px] text-muted">
                Nothing out for grading
              </p>
            </div>
          )}
          {returned.length > 0 && (
            <div className="mt-5 border-t border-border pt-4">
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

        <Card className="p-5 sm:p-6">
          <SectionTitle
            title="Worth grading"
            subtitle={`Most upside as a PSA 10, after ${money(costs.fee + costs.shipping)} in costs`}
            action={
              <Button variant="ghost" size="sm" onClick={() => setCostsOpen(true)}>
                Costs
              </Button>
            }
          />
          {candidates.length ? (
            <ul className="divide-y divide-border">
              {(showAll ? candidates : candidates.slice(0, CANDIDATES)).map(({ h, outlook }) => (
                <CandidateRow key={h.key} h={h} outlook={outlook} away={atGrader.get(h.key) ?? 0} />
              ))}
            </ul>
          ) : (
            <p className="py-6 text-center text-[13px] text-muted">No raw singles worth more than {money(MIN_RAW)} with upside after grading costs.</p>
          )}
          {candidates.length > CANDIDATES && (
            <button type="button" onClick={() => setShowAll((v) => !v)} className="mt-3 text-[13px] font-medium text-muted hover:text-foreground">
              {showAll ? "Show fewer" : `Show all ${candidates.length}`}
            </button>
          )}
        </Card>
      </div>

      <section className="mt-10">
        <SectionTitle title="Your slabs" subtitle={slabs.length ? "Graded cards, by value" : undefined} />
        {slabs.length ? (
          <div className="grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-5">
            {slabs.map((h) => (
              <SlabTile key={h.key} h={h} today={store.today} summary={summaryOf(h)} />
            ))}
          </div>
        ) : (
          <p className="text-[13px] text-muted">No graded cards yet. Add one with “Graded card” switched on, or mark a submission as returned.</p>
        )}
      </section>

      <CostsDialog open={costsOpen} onOpenChange={setCostsOpen} />
    </div>
  );
}

function SubmissionRow({ s }: { s: GradingSubmission }) {
  const { data, today } = useStore();
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const { cancel } = useGradingSubmissions();
  const [open, setOpen] = useState(false);
  const product = data.products[s.productId];
  const holding = holdings.find((h) => h.key === holdingKey({ productId: s.productId, printing: s.printing, condition: s.condition, grade: null }));
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

function CandidateRow({ h, outlook, away }: { h: HoldingView; outlook: ReturnType<typeof gradingOutlook>; away: number }) {
  const [open, setOpen] = useState(false);
  return (
    <li className="flex items-center gap-3 py-3">
      <ProductImage product={h.product} size="xs" className="size-11 shrink-0 rounded-lg" />
      <div className="min-w-0 flex-1">
        <Link href={`/product/${encodeURIComponent(h.identity.productId)}`} className="block truncate text-[14px] font-medium hover:underline">
          {h.product?.name ?? "Card"}
        </Link>
        <p className="tabular truncate text-[12px] text-muted">
          Raw {money(outlook.raw)} · PSA 10 {outlook.source === "estimate" ? "≈" : ""}
          {money(outlook.psa10)} · PSA 9 {outlook.source === "estimate" ? "≈" : ""}
          {money(outlook.psa9)}
        </p>
        <p className={cn("text-[11px]", liquidityOf(outlook.psa10Sales) === "rare" ? "text-subtle" : "text-muted")}>
          PSA 10s: {liquidityLabel(outlook.psa10Sales).toLowerCase()}
          {outlook.source === "sales" && " · eBay"}
          {outlook.source === "estimate" && " · estimated, few recent sales"}
        </p>
      </div>
      <div className="shrink-0 text-right">
        <p className="tabular text-[14px] font-semibold">
          <span className="text-up">{signedMoney(outlook.upside10)}</span>
        </p>
        <p className="tabular text-[11px] text-muted">
          at a 9: <span className={outlook.upside9 >= 0 ? "text-up" : "text-down"}>{signedMoney(outlook.upside9)}</span>
        </p>
      </div>
      {away >= h.quantity ? (
        <span className="w-9 shrink-0 text-center text-[11px] text-subtle">Sent</span>
      ) : (
        <Button variant="ghost" size="icon-sm" aria-label="Send for grading" onClick={() => setOpen(true)}>
          <Send />
        </Button>
      )}
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
      <p className={cn("text-[11px]", stale ? "text-foreground/80" : "text-subtle")}>
        {manual ? (stale ? `Your value · ${daysBetween(h.priceUpdatedAt!, today)} days old` : "Your value") : slabSourceLabel(h)}
      </p>
      {raw !== null && h.identity.grade && (
        <p className="text-[11px] text-subtle">
          {liquidityLabel(summary ? (summary.graded[gradeLabel(h.identity.grade)]?.count ?? 0) * 12 : sampleSalesPerYear(h.identity.productId, h.identity.grade, raw))}
        </p>
      )}
    </Link>
  );
}

function CostsDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (o: boolean) => void }) {
  const { costs, setCosts } = useGradingCosts();
  const [fee, setFee] = useState("");
  const [shipping, setShipping] = useState("");
  useEffect(() => {
    if (!open) return;
    setFee(costs.fee.toFixed(2));
    setShipping(costs.shipping.toFixed(2));
  }, [open, costs]);
  const f = parseMoney(fee);
  const s = parseMoney(shipping);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Grading costs"
          description="Used to weigh which cards are worth grading, and as the default when you send one in."
          onSubmit={(e) => {
            e.preventDefault();
            if (f === null || s === null) return;
            setCosts({ fee: f, shipping: s });
            toast.success("Grading costs saved");
            onOpenChange(false);
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full" disabled={f === null || s === null}>
              Save
            </Button>
          }
        >
          <div className="grid grid-cols-2 gap-3">
            <Field label="Fee per card" htmlFor="cost-fee">
              <MoneyInput id="cost-fee" value={fee} onChange={setFee} />
            </Field>
            <Field label="Shipping per card" htmlFor="cost-shipping" hint="Both ways, with insurance">
              <MoneyInput id="cost-shipping" value={shipping} onChange={setShipping} />
            </Field>
          </div>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}
