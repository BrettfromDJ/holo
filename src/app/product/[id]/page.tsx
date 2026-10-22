"use client";

import { ChevronLeft, Eye, EyeOff, ExternalLink, Loader2, MoreHorizontal, Plus, Tag } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { ScrubChart } from "@/components/charts/scrub-chart";
import { AdjustDialog, CorrectionDialog, ManualValueDialog, SaleDialog } from "@/components/flows/transaction-dialogs";
import { ErrorState } from "@/components/portfolio/error-state";
import { holdingLabel } from "@/components/portfolio/holding-items";
import { Delta, DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, SectionTitle } from "@/components/ui/card";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { categoryOf } from "@/lib/catalog";
import { addDays } from "@/lib/finance/dates";
import { acquisitionCost, effectiveTransactions, saleProceeds } from "@/lib/finance/ledger";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, relativeTime, tone } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { priceKey, type Transaction } from "@/lib/types";

type HistRange = "1M" | "3M" | "1Y" | "ALL";
const HIST_DAYS: Record<HistRange, number | null> = { "1M": 30, "3M": 91, "1Y": 365, ALL: null };

export default function ProductPage() {
  const params = useParams<{ id: string }>();
  const productId = decodeURIComponent(params.id);
  const store = useStore();
  const { holdings, realized } = usePortfolio();
  const product = store.data.products[productId];
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // Products not yet in the local catalog (e.g. deep links) are fetched once.
  useEffect(() => {
    if (store.status !== "ready" || product || loading || loadError) return;
    setLoading(true);
    store
      .importProduct(productId)
      .catch((e: Error) => setLoadError(e.message))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.status, product, productId]);

  if (store.status === "loading" || (!product && loading)) return <ProductSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!product) return <ErrorState message={loadError ?? "This product couldn't be found."} />;

  const owned = holdings.filter((h) => h.identity.productId === productId);
  const realizedHere = realized.filter((r) => r.holdingKey.startsWith(`${productId}|`)).reduce((s, r) => s + r.gain, 0);
  const printing = owned[0]?.identity.printing ?? product.printings?.[0] ?? null;
  const price = store.data.prices[priceKey(productId, printing)];
  const watch = store.data.watchlist.find((w) => w.productId === productId);

  return (
    <div className="animate-fade-in">
      <Link href="/collection" className="mb-6 inline-flex items-center gap-1 text-[14px] text-muted hover:text-foreground">
        <ChevronLeft className="size-4" /> Collection
      </Link>

      <div className="grid gap-8 lg:grid-cols-[minmax(0,420px)_1fr] lg:gap-12">
        <ProductImage product={product} size="xl" priority className="aspect-square w-full rounded-[1.75rem] lg:sticky lg:top-10" />

        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <Badge>{categoryOf(product)}</Badge>
            {product.rarity && <Badge variant="outline">{product.rarity}</Badge>}
            {product.source === "sample" && <Badge variant="sample">Sample data</Badge>}
          </div>
          <h1 className="mt-3 text-[28px] font-semibold leading-tight tracking-[-0.02em] sm:text-[36px]">{product.name}</h1>
          <p className="mt-1 text-[15px] text-muted">
            {[product.setName, product.number ? `#${product.number}` : null, printing && printing !== "Normal" ? printing : null].filter(Boolean).join(" · ")}
          </p>

          <div className="mt-6">
            <p className="tabular text-[40px] font-semibold leading-none tracking-[-0.03em]">{price?.market != null ? money(price.market) : <span className="text-muted">No price</span>}</p>
            <div className="mt-3 flex flex-wrap items-center gap-2 text-[13px]">
              {(["24h", "7d", "30d"] as const).map((p) => {
                const v = p === "24h" ? price?.change24hPct : p === "7d" ? price?.change7dPct : price?.change30dPct;
                return (
                  <span key={p} className="inline-flex items-center gap-1.5 rounded-full bg-surface px-2.5 py-1">
                    <span className="text-subtle">{p}</span>
                    <DeltaPill ratio={v == null ? null : v / 100} className="px-0 py-0 bg-transparent" />
                  </span>
                );
              })}
            </div>
            <p className="mt-3 text-[12px] text-subtle">
              {price
                ? `${price.source === "sample" ? "Sample price" : "Market price via TCG API"} · ${price.status === "stale" ? "stale · " : ""}updated ${relativeTime(price.updatedAt)}`
                : "No market price available — not counted as $0."}
            </p>
          </div>

          <div className="mt-6 flex flex-wrap gap-2">
            <Button variant="primary" onClick={() => store.openAdd({ productId })}>
              <Plus /> {owned.length ? "Add more" : "Add to collection"}
            </Button>
            {owned.length === 1 && <SaleButton holding={owned[0]} />}
            <WatchButton productId={productId} printing={printing} watchId={watch?.id} />
            {product.tcgplayerUrl && (
              <Button variant="ghost" asChild>
                <a href={product.tcgplayerUrl} target="_blank" rel="noreferrer">
                  TCGplayer <ExternalLink />
                </a>
              </Button>
            )}
          </div>

          <PriceHistory productId={productId} printing={printing} />

          {owned.length > 0 && <Position holdings={owned} realized={realizedHere} />}
          {owned.length === 0 && realizedHere !== 0 && (
            <Card className="mt-6 p-5">
              <p className="text-[13px] text-muted">Position closed · realized</p>
              <Delta value={realizedHere} className="mt-1 text-[20px] font-semibold" />
            </Card>
          )}
          <History productId={productId} />
        </div>
      </div>
    </div>
  );
}

function SaleButton({ holding }: { holding: HoldingView }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button variant="secondary" onClick={() => setOpen(true)}>
        <Tag /> Record sale
      </Button>
      <SaleDialog holding={holding} open={open} onOpenChange={setOpen} />
    </>
  );
}

function WatchButton({ productId, printing, watchId }: { productId: string; printing: string | null; watchId?: string }) {
  const { addWatch, removeWatch } = useStore();
  const [busy, setBusy] = useState(false);
  return (
    <Button
      variant="secondary"
      disabled={busy}
      onClick={async () => {
        setBusy(true);
        try {
          if (watchId) {
            await removeWatch(watchId);
            toast("Removed from watchlist");
          } else {
            await addWatch(productId, printing, null);
            toast.success("Added to watchlist");
          }
        } catch (e) {
          toast.error((e as Error).message);
        } finally {
          setBusy(false);
        }
      }}
    >
      {busy ? <Loader2 className="animate-spin" /> : watchId ? <EyeOff /> : <Eye />}
      {watchId ? "Watching" : "Watch"}
    </Button>
  );
}

function PriceHistory({ productId, printing }: { productId: string; printing: string | null }) {
  const { data, today } = useStore();
  const [range, setRange] = useState<HistRange>("3M");
  const [scrub, setScrub] = useState<number | null>(null);
  const key = priceKey(productId, printing);

  const series = useMemo(() => {
    const pts = [...(data.history[key] ?? [])].filter((p) => p.date < today);
    const current = data.prices[key];
    if (current?.market != null) pts.push({ date: today, price: current.market });
    return pts;
  }, [data.history, data.prices, key, today]);

  const sliced = useMemo(() => {
    const days = HIST_DAYS[range];
    const from = days === null ? "" : addDays(today, -days);
    return series.filter((p) => p.date >= from);
  }, [series, range, today]);

  const first = sliced[0];
  const at = scrub !== null && sliced[scrub] ? sliced[scrub] : sliced[sliced.length - 1];
  const change = first && at ? at.price - first.price : null;
  const isSample = data.prices[key]?.source === "sample";

  return (
    <Card className="mt-8 p-5 sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-[15px] font-semibold">Market price history</h2>
          <p className="tabular mt-1 text-[13px]">
            {at ? (
              <>
                <span className="font-medium">{money(at.price)}</span> <Delta value={change} ratio={first && change !== null ? change / first.price : null} />{" "}
                <span className="text-muted">{scrub !== null ? formatDate(at.date) : `since ${formatDate(first.date)}`}</span>
              </>
            ) : (
              <span className="text-muted">No history</span>
            )}
          </p>
        </div>
        <Segmented ariaLabel="History range" size="sm" value={range} onChange={setRange} options={(["1M", "3M", "1Y", "ALL"] as HistRange[]).map((r) => ({ value: r, label: r }))} />
      </div>
      <div className="mt-4">
        {sliced.length > 1 ? (
          <ScrubChart data={sliced.map((p) => ({ date: p.date, value: p.price }))} tone={tone(sliced[sliced.length - 1].price - sliced[0].price)} baseline={sliced[0].price} onScrub={setScrub} height={220} />
        ) : (
          <div className="flex h-[220px] flex-col items-center justify-center rounded-2xl border border-dashed border-border px-6 text-center text-[13px] text-muted">
            <p className="font-medium text-foreground">Not enough price history yet</p>
            <p className="mt-1 max-w-sm">
              History depends on your TCG API plan. Holo stores a daily snapshot for products you own or watch, so this chart fills in over time. Missing days are never filled with estimates.
            </p>
          </div>
        )}
      </div>
      <p className="mt-2 text-[11px] text-subtle">
        {isSample ? "Sample series for demonstration — not market data." : `${series.length} daily observation${series.length === 1 ? "" : "s"} · gaps are shown as-is, never interpolated`}
      </p>
    </Card>
  );
}

function Position({ holdings, realized }: { holdings: HoldingView[]; realized: number }) {
  const qty = holdings.reduce((s, h) => s + h.quantity, 0);
  const priced = holdings.filter((h) => h.value !== null);
  const value = priced.reduce((s, h) => s + (h.value ?? 0), 0);
  const cost = holdings.reduce((s, h) => s + h.costBasis, 0);
  const pricedCost = priced.reduce((s, h) => s + h.costBasis, 0);
  const unrealized = priced.length ? value - pricedCost : null;
  return (
    <Card className="mt-6 p-5 sm:p-6">
      <SectionTitle title="Your position" />
      <dl className="grid grid-cols-2 gap-x-6 gap-y-5 sm:grid-cols-3">
        <Stat label="Quantity" value={String(qty)} />
        <Stat label="Holding value" value={priced.length ? money(value) : "—"} />
        <Stat label="Cost basis" value={money(cost)} />
        <Stat label="Average cost" value={money(cost / qty)} />
        <Stat label="Unrealized" value={<Delta value={unrealized} ratio={unrealized !== null && pricedCost > 0 ? unrealized / pricedCost : null} />} />
        <Stat label="Realized" value={<Delta value={realized} />} />
      </dl>
      <div className="mt-6 divide-y divide-border border-t border-border">
        {holdings.map((h) => (
          <HoldingLine key={h.key} h={h} />
        ))}
      </div>
    </Card>
  );
}

function HoldingLine({ h }: { h: HoldingView }) {
  const [dialog, setDialog] = useState<"sale" | "adjust" | "value" | null>(null);
  return (
    <div className="flex items-center gap-3 py-3.5">
      <div className="min-w-0 flex-1">
        <p className="text-[14px] font-medium">
          {h.quantity} × {holdingLabel(h) ?? h.identity.condition}
        </p>
        <p className="tabular text-[12px] text-muted">
          {h.lots.length} open lot{h.lots.length === 1 ? "" : "s"} · avg {money(h.avgCost)}
          {h.identity.grade && ` · valued ${money(h.price)} (manual)`}
        </p>
      </div>
      <Delta value={h.unrealized} ratio={h.unrealizedPct} className="text-[13px]" />
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon-sm" aria-label="Holding actions">
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onSelect={() => setDialog("sale")}>Record sale</DropdownMenuItem>
          <DropdownMenuItem onSelect={() => setDialog("adjust")}>Adjust quantity</DropdownMenuItem>
          {h.identity.grade && <DropdownMenuItem onSelect={() => setDialog("value")}>Update valuation</DropdownMenuItem>}
        </DropdownMenuContent>
      </DropdownMenu>
      <SaleDialog holding={h} open={dialog === "sale"} onOpenChange={(o) => !o && setDialog(null)} />
      <AdjustDialog holding={h} open={dialog === "adjust"} onOpenChange={(o) => !o && setDialog(null)} />
      {h.identity.grade && <ManualValueDialog holding={h} open={dialog === "value"} onOpenChange={(o) => !o && setDialog(null)} />}
    </div>
  );
}

function History({ productId }: { productId: string }) {
  const { data } = useStore();
  const [correcting, setCorrecting] = useState<Transaction | null>(null);
  const all = data.transactions.filter((t) => t.productId === productId);
  if (!all.length) return null;
  const effective = new Map(effectiveTransactions(all).map((t) => [t.id, t]));
  const rows = [...all].sort((a, b) => (a.date === b.date ? (a.createdAt < b.createdAt ? 1 : -1) : a.date < b.date ? 1 : -1));
  const notes = all.filter((t) => t.notes);

  return (
    <>
      <Card className="mt-6 p-5 sm:p-6">
        <SectionTitle title="Purchase history" subtitle="Every entry is kept. Corrections are added, never overwritten." />
        <ul className="divide-y divide-border">
          {rows.map((t) => {
            const eff = effective.get(t.id);
            const voided = t.type !== "correction" && !eff;
            const shown = eff ?? t;
            const amount = t.type === "sale" ? saleProceeds(shown) : t.type === "correction" ? null : acquisitionCost(shown);
            return (
              <li key={t.id} className="flex items-center gap-3 py-3">
                <div className="min-w-0 flex-1">
                  <p className="text-[14px] font-medium capitalize">
                    {t.type === "adjustment" ? (t.quantity > 0 ? "Added" : "Removed") : t.type}
                    {t.type !== "correction" && (
                      <span className="tabular font-normal text-muted">
                        {" "}
                        · {Math.abs(shown.quantity)} × {money(shown.unitPrice)}
                      </span>
                    )}
                    {voided && <Badge className="ml-2">Voided</Badge>}
                    {eff && eff !== t && (eff.unitPrice !== t.unitPrice || eff.quantity !== t.quantity || eff.date !== t.date) && <Badge className="ml-2">Corrected</Badge>}
                  </p>
                  <p className="truncate text-[12px] text-muted">
                    {formatDate(shown.date)}
                    {t.source && ` · ${t.source}`}
                    {t.type === "correction" && t.notes && ` · ${t.notes}`}
                  </p>
                </div>
                {amount !== null && <span className={`tabular text-[14px] ${voided ? "text-subtle line-through" : ""}`}>{t.type === "sale" ? "+" : ""}{money(amount)}</span>}
                {t.type !== "correction" && !voided && (
                  <Button variant="ghost" size="sm" onClick={() => setCorrecting(t)}>
                    Correct
                  </Button>
                )}
              </li>
            );
          })}
        </ul>
      </Card>
      {notes.length > 0 && (
        <Card className="mt-6 p-5 sm:p-6">
          <SectionTitle title="Notes" />
          <ul className="space-y-3">
            {notes.map((t) => (
              <li key={t.id} className="text-[14px]">
                <p>{t.notes}</p>
                <p className="mt-0.5 text-[12px] text-subtle">{formatDate(t.date)}</p>
              </li>
            ))}
          </ul>
        </Card>
      )}
      <CorrectionDialog tx={correcting} open={correcting !== null} onOpenChange={(o) => !o && setCorrecting(null)} />
    </>
  );
}

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <dt className="text-[12px] text-muted">{label}</dt>
      <dd className="tabular mt-1 text-[17px] font-semibold">{value}</dd>
    </div>
  );
}

function ProductSkeleton() {
  return (
    <div className="grid gap-8 lg:grid-cols-[420px_1fr]" aria-busy="true">
      <Skeleton className="aspect-square w-full rounded-[1.75rem]" />
      <div>
        <Skeleton className="h-5 w-24" />
        <Skeleton className="mt-4 h-10 w-3/4" />
        <Skeleton className="mt-6 h-12 w-40" />
        <Skeleton className="mt-8 h-64 w-full rounded-3xl" />
      </div>
    </div>
  );
}
