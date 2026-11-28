"use client";

import { useHeroTarget } from "@/lib/motion/hero";
import { BumperDialog, CertDialog, GradeChip } from "@/components/grading/grading-items";
import { Check, ChevronRight, ExternalLink, Loader2, MoreHorizontal, Plus } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { ScrubChart, type ChartMarker } from "@/components/charts/scrub-chart";
import { TransactionActions, partitionHistory } from "@/components/flows/transaction-dialogs";
import { ErrorState } from "@/components/portfolio/error-state";
import { holdingLabel } from "@/components/portfolio/holding-items";
import { HoldingSheet } from "@/components/portfolio/holding-sheet";
import { Delta, DeltaPill } from "@/components/product/delta";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { Reveal } from "@/components/motion/reveal";
import { HoloTilt, isFoilCard } from "@/components/motion/holo-tilt";
import { ProductImage } from "@/components/product/product-image";
import { ChipTiles } from "@/components/product/chip-tiles";
import { PageActions } from "@/components/product/page-actions";
import { SimilarCards } from "@/components/product/similar-cards";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, SectionTitle } from "@/components/ui/card";
import { ConditionTag, EbaySales } from "@/components/product/ebay-sales";
import { WhatsItWorth } from "@/components/product/whats-it-worth";
import { Skeleton } from "@/components/ui/skeleton";
import { bumperById } from "@/lib/bumpers";
import { categoryOf } from "@/lib/catalog";
import { packCount, pricePerPack } from "@/lib/packs";
import { addDays } from "@/lib/finance/dates";
import { acquisitionCost, effectiveTransactions, saleProceeds } from "@/lib/finance/ledger";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, relativeTime, signedPct, tone } from "@/lib/format";
import { certLookupUrl, gradeLabel } from "@/lib/graded";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useSlabBumpers, useSlabCerts } from "@/lib/store/grading";
import { priceKey, type Product, type Transaction } from "@/lib/types";
import { cn } from "@/lib/utils";
import { orderPrintings, withEditionArt } from "@/lib/editions";
import { PriceInfoDialog, type PriceInfoData } from "@/components/product/price-info";
import { isStalePrice, priceAge } from "@/lib/price-info";

type HistRange = "1M" | "3M" | "1Y" | "ALL";
const HIST_DAYS: Record<HistRange, number | null> = { "1M": 30, "3M": 91, "1Y": 365, ALL: null };

export default function ProductPage() {
  const params = useParams<{ id: string }>();
  const productId = decodeURIComponent(params.id);
  const store = useStore();
  const { holdings, realized } = usePortfolio({ ignoreFilter: true });
  const product = store.data.products[productId];
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // Products not in this collection (Explore, deep links) come from the stored
  // catalog first, which costs no TCG API requests; only unknown ones are fetched.
  useEffect(() => {
    if (store.status !== "ready" || product || loading || loadError) return;
    setLoading(true);
    (productId.startsWith("sample:") ? Promise.resolve(false) : store.showCatalogProduct(productId).catch(() => false))
      .then((found) => (found ? undefined : store.importProduct(productId)))
      .catch((e: Error) => setLoadError(e.message))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [store.status, product, productId]);

  // Lets a card tapped in a grid fly into the image spot once the page has it.
  const hero = useHeroTarget(store.status === "ready" && Boolean(product));
  // The printing on show: one picked here or passed in the link (?printing=, from search and
  // set grids), else the one you own, else the first priced one.
  const [chosenPrinting, setChosenPrinting] = useState<string | null>(null);
  // The headline price's "where it comes from" dialog.
  const [priceInfo, setPriceInfo] = useState<PriceInfoData | null>(null);
  useEffect(() => {
    setChosenPrinting(new URLSearchParams(window.location.search).get("printing"));
  }, [productId]);
  const choosePrinting = (p: string) => {
    setChosenPrinting(p);
    const url = new URL(window.location.href);
    url.searchParams.set("printing", p);
    window.history.replaceState(null, "", url);
  };

  if (store.status === "loading" || (!product && loading)) return <ProductSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!product) return <ErrorState message={loadError ?? "This product couldn't be found."} />;

  const owned = holdings.filter((h) => h.identity.productId === productId);
  const yourCopies = owned.filter((h) => h.price !== null && (h.identity.grade || h.conditionEstimate));
  const realizedHere = realized.filter((r) => r.holdingKey.startsWith(`${productId}|`)).reduce((s, r) => s + r.gain, 0);
  const printing = chosenPrinting ?? owned[0]?.identity.printing ?? orderPrintings(product.printings ?? [])[0] ?? null;
  // The Unlimited printing of an old set shows the Unlimited print's photo, not the 1st Edition scan.
  const art = withEditionArt(product, printing);
  // Unlimited first, then 1st Edition.
  const printings = orderPrintings([...new Set([...(product.printings ?? []), ...owned.map((h) => h.identity.printing).filter((p): p is string => Boolean(p))])]);
  const price = store.data.prices[priceKey(productId, printing)];
  // No current price (older or unsynced products): fall back to the latest point in its price
  // history, labelled with its date, and work the 24h/7d/30d changes out from the history.
  const hist = [...(store.data.history[priceKey(productId, printing)] ?? [])].sort((a, b) => (a.date < b.date ? -1 : 1));
  const lastPoint = hist.length ? hist[hist.length - 1] : null;
  const headline = price?.market ?? lastPoint?.price ?? null;
  const histChange = (days: number): number | null => {
    if (!lastPoint) return null;
    const cutoff = addDays(lastPoint.date, -days);
    const base = [...hist].reverse().find((p) => p.date <= cutoff);
    return base && base.price > 0 ? ((lastPoint.price - base.price) / base.price) * 100 : null;
  };
  const slab = owned.length > 0 && owned.every((h) => h.identity.grade) ? owned[0].identity.grade : null;
  const owns = owned.reduce((s, h) => s + h.quantity, 0);
  const stageLine = [product.setName, product.number ? `#${product.number}` : null].filter(Boolean).join(" · ");
  // The set's name opens its page in Explore when the catalog has it.
  const setHref = product.setId && product.source === "tcgapi" ? `/explore/${encodeURIComponent(product.setId)}` : null;
  const rest = [product.number ? `#${product.number}` : null, printings.length < 2 && printing && printing !== "Normal" ? printing : null].filter(Boolean).join(" · ");

  return (
    <div className="animate-fade-in">
      {/* What it is and its rarity at the top, and everything you can do with it in one ⋯ (the app's toolbar). */}
      <div className="mb-4 flex items-center justify-between gap-3">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <span className="inline-flex h-[22px] items-center rounded-full border border-white/10 bg-white/[0.06] px-[9px] text-[12px] font-medium text-muted backdrop-blur-xl">
            {product.kind === "sealed" ? (product.productType ?? categoryOf(product)) : "Card"}
          </span>
          {product.rarity && <Badge variant="outline" className="h-[22px] px-[9px] text-[12px]">{product.rarity}</Badge>}
          {product.source === "sample" && <Badge variant="sample">Sample data</Badge>}
        </div>
        <PageActions product={product} printing={printing} price={price?.market ?? null} owned={owned} />
      </div>

      <div className="grid gap-8 lg:grid-cols-[minmax(0,420px)_1fr] lg:gap-12">
        <div className="flex flex-col items-center gap-[22px] self-start lg:sticky lg:top-10">
          {/* Above the piece: the set and number, and whether (and how many) you own. */}
          {(stageLine || owns > 0) && (
            <div className="flex flex-col items-center gap-2.5 text-center">
              {stageLine && <p className="font-mono text-[11px] font-medium uppercase tracking-[0.06em] text-subtle">{stageLine}</p>}
              {owns > 0 && (
                <span className="tag-skew tag-lime">
                  <Check className="size-2.5" strokeWidth={3} /> Owned{owns > 1 ? ` ×${owns}` : ""}
                </span>
              )}
            </div>
          )}
          {slab ? (
            // Only slabs of this card are owned: show it in its slab.
            <HoloTilt heroName={hero.name} radius="7% / 4.4%" foil={false} className={`mx-auto aspect-[5/8] w-full max-w-[260px] ${hero.arriving ? "" : "animate-pop"} sm:max-w-[340px]`}>
              <ProductImage product={art} grade={slab} slabKey={owned[0]?.key} size="xl" priority className="h-full w-full" />
            </HoloTilt>
          ) : product.kind === "single" && product.imageUrl ? (
            // A bare card: no well or frame, just the card at its own proportions.
            <HoloTilt heroName={hero.name} radius="4.5% / 3.2%" foil={isFoilCard(product)} className={`mx-auto aspect-[63/88] w-full max-w-[260px] ${hero.arriving ? "" : "animate-pop"} sm:max-w-[360px]`}>
              <ProductImage product={art} size="xl" priority frame={false} className="h-full w-full rounded-[4.5%/3.2%] shadow-2xl shadow-black/50" />
            </HoloTilt>
          ) : (
            <HoloTilt heroName={hero.name} radius="1.75rem" foil={false} className={`aspect-square w-full ${hero.arriving ? "" : "animate-pop"}`}>
              <ProductImage product={art} size="xl" priority className="h-full w-full rounded-[1.75rem]" />
            </HoloTilt>
          )}
        </div>

        <div className="min-w-0">
          <h1 className="font-display text-[34px] leading-[1.02] tracking-[-0.02em] [text-wrap:balance]">{product.name}</h1>
          {/* The set's name opens the set, then number and printing. */}
          <p className="mt-1.5 text-[15px] text-muted [text-wrap:pretty]">
            {product.setName &&
              (setHref ? (
                <Link href={setHref} aria-label={`Open the set ${product.setName}`} className="text-foreground underline decoration-white/35 underline-offset-[3px] hover:decoration-white/70">
                  {product.setName}
                  {"\u00a0"}
                  <ChevronRight className="inline size-3 -translate-y-px text-muted" strokeWidth={3} />
                </Link>
              ) : (
                <span>{product.setName}</span>
              ))}
            {rest && <span>{product.setName ? " · " : ""}{rest}</span>}
          </p>
          {product.artist && (
            <Link href={`/artist/${encodeURIComponent(product.artist)}`} className="mt-1 inline-block text-[14px] text-muted">
              Illustrated by <span className="text-foreground underline decoration-white/35 underline-offset-[3px] hover:decoration-white/70">{product.artist}</span>
              {"\u00a0"}
              <ChevronRight className="inline size-3 -translate-y-px text-muted" strokeWidth={3} />
            </Link>
          )}
          {/* Different printings sell for different prices: switch between them. */}
          {printings.length > 1 && <ChipTiles ariaLabel="Printing" className="mt-3.5" value={printing ?? printings[0]} onChange={choosePrinting} options={printings.map((p) => ({ value: p, label: p }))} />}

          <div className="mt-3">
            {/* Click the price: where it comes from and what eBay's recent sales say. An old price stays white; the line under it says when it's from. */}
            <button
              type="button"
              onClick={() =>
                setPriceInfo({
                  title: product.kind === "sealed" ? "Market price" : "TCGplayer market price · ungraded",
                  value: headline,
                  rows: [
                    ["Source", price?.source === "pricecharting" ? "PriceCharting (TCGplayer has no price)" : price ? "TCGplayer market price" : "Last stored price"],
                    ...(priceAge(price?.updatedAt) ? ([["Updated", priceAge(price?.updatedAt)!]] as [string, string][]) : []),
                    ...(printing ? ([["Printing", printing]] as [string, string][]) : []),
                  ],
                  ebay: { productId, printing, grade: null },
                  note: isStalePrice(price?.updatedAt) ? "This price is more than 3 days old; it refreshes with the daily sync." : null,
                  stale: isStalePrice(price?.updatedAt),
                })
              }
              className="tabular block cursor-pointer text-left font-display text-[52px] leading-none tracking-[-2.1px]"
            >
              {headline != null ? <AnimatedNumber key={productId} value={headline} format={money} from={headline * 0.85} /> : <span className="text-muted">No price</span>}
            </button>
            <PriceInfoDialog info={priceInfo} onOpenChange={(o) => !o && setPriceInfo(null)} />
            {product.kind === "sealed" ? <PerPack product={product} price={headline} /> : <p className="mt-1 text-[13px] text-muted">TCGplayer market price · ungraded</p>}
            {/* The headline is the card's Near Mint price; copies you own that differ get their own figure here. */}
            {yourCopies.length > 0 && (
              <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-[13px] text-muted">
                {yourCopies.map((h) => (
                  <span key={h.key} className="inline-flex items-center gap-1">
                    Your {h.identity.grade ? <GradeChip grade={h.identity.grade} /> : <ConditionTag condition={h.identity.condition} />}
                    {h.quantity > 1 && <span className="tabular">×{h.quantity}</span>} <span className="tabular font-semibold text-foreground">{h.conditionEstimate ? "≈ " : ""}{money(h.price)}</span>
                  </span>
                ))}
              </div>
            )}
            <div className="mt-3 flex flex-wrap items-center gap-2 text-[13px]">
              {(["24h", "7d", "30d"] as const).map((p) => {
                const v = p === "24h" ? (price?.change24hPct ?? histChange(1)) : p === "7d" ? (price?.change7dPct ?? histChange(7)) : (price?.change30dPct ?? histChange(30));
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
                ? `${price.source === "sample" ? "Sample price" : price.source === "pricecharting" ? "Ungraded price via PriceCharting (no TCGplayer price)" : "Market price via TCG API"} · ${price.status === "stale" ? "stale · " : ""}updated ${relativeTime(price.updatedAt)}`
                : lastPoint
                  ? `Last market price ${formatDate(lastPoint.date)} · no current price yet`
                  : "No market price available. Not counted as $0."}
              {price && price.source !== "pricecharting" && product.tcgplayerUrl && (
                <>
                  {" · "}
                  <a href={product.tcgplayerUrl} target="_blank" rel="noreferrer" className="font-semibold text-foreground hover:underline">
                    TCGplayer ↗
                  </a>
                </>
              )}
            </p>
          </div>

          {/* A card you own opens here straight away: how yours are doing comes first. */}
          {owned.length > 0 && <Position product={product} holdings={owned} realized={realizedHere} />}

          {/* One lime button; everything else is in the ⋯ at the top right. Then the card on TCGplayer. */}
          <div className="mt-6">
            <button
              type="button"
              onClick={() => store.openAdd({ productId })}
              className="btn-3d btn-3d-lime flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-lime text-[15px] font-semibold text-[#0b0b0c] transition-transform active:scale-[0.98]"
            >
              <Plus className="size-4" strokeWidth={2.5} /> {owned.length ? "Add more" : "Add to Collection"}
            </button>
            {product.kind === "single" && <WhatsItWorth nm={price?.market ?? null} tcgplayerUrl={product.tcgplayerUrl} tcgplayerId={product.tcgplayerId} printing={printing} />}
          </div>

          <Reveal delay={80}>
            <PriceHistory productId={productId} printing={printing} />
          </Reveal>

          {(product.source === "tcgapi" || product.source === "sample") && (
            <Reveal>
              <EbaySales productId={productId} printing={printing} grade={owned.find((h) => h.identity.grade)?.identity.grade ?? null} className="mt-6" />
            </Reveal>
          )}

          {owned.some((h) => h.identity.grade) && <YourSlabs holdings={owned.filter((h) => h.identity.grade)} />}
          {owned.length === 0 && realizedHere !== 0 && (
            <Card className="mt-6 p-5">
              <p className="text-[13px] text-muted">Position closed · realized</p>
              <Delta value={realizedHere} className="mt-1 text-[20px] font-semibold" />
            </Card>
          )}
          <Reveal>
            <History productId={productId} />
          </Reveal>
          {product.kind === "single" && <SimilarCards product={product} />}
        </div>
      </div>
    </div>
  );
}

/** Market price per booster pack for sealed products, when the pack count is known. */
function PerPack({ product, price }: { product: Product; price: number | null }) {
  const [gameSlug, setGameSlug] = useState<string | null>(null);
  const direct = packCount(product);
  // Booster boxes differ by game; look the set's game up in the stored catalog (no TCG API request).
  useEffect(() => {
    if (direct || !product.setId || product.source !== "tcgapi" || !/booster (box|display)/i.test(product.name)) return;
    let cancelled = false;
    fetch(`/api/explore/sets/${encodeURIComponent(product.setId)}?meta=1`)
      .then((r) => (r.ok ? r.json() : null))
      .then((b) => !cancelled && b?.set?.gameSlug && setGameSlug(b.set.gameSlug))
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [direct, product.setId, product.source, product.name]);
  const count = direct ?? packCount(product, gameSlug ?? (product.source === "sample" ? "pokemon" : null));
  const per = pricePerPack(price, count);
  if (per === null || !count) return null;
  return (
    <p className="tabular mt-2 text-[14px] text-muted">
      <span className="font-medium text-foreground">{money(per)}</span> per pack · {count.packs} pack{count.packs === 1 ? "" : "s"}
      {!count.exact && <span className="text-subtle"> (standard contents)</span>}
    </p>
  );
}

/**
 * Load a product's full price history automatically when the page opens and Holo has less
 * than two months of it (the app does the same). The server answers from storage when it can
 * and otherwise makes one TCG API request, then stores it for everyone. Asked once per
 * product and printing per visit.
 */
const askedHistory = new Set<string>();
function useFullHistory(productId: string, printing: string | null, needed: boolean) {
  const { mergeHistory } = useStore();
  const [state, setState] = useState<{ status: "idle" | "loading" | "done" | "error"; note?: string }>({ status: "idle" });
  const load = useCallback(async () => {
    setState({ status: "loading" });
    try {
      const res = await fetch(`/api/explore/products/${encodeURIComponent(productId)}/history`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ printing }),
      });
      const body = await res.json().catch(() => null);
      if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't load price history.");
      mergeHistory(productId, printing, body.points ?? []);
      setState({
        status: "done",
        note: !body.available ? (body.reason ?? "Price history isn't available right now.") : !body.points?.length ? "No price history is available for this product." : undefined,
      });
    } catch (e) {
      setState({ status: "error", note: (e as Error).message });
    }
  }, [productId, printing, mergeHistory]);
  useEffect(() => {
    const key = `${productId}|${printing ?? ""}`;
    if (!needed || askedHistory.has(key)) return;
    askedHistory.add(key);
    void load();
  }, [productId, printing, needed, load]);
  return { ...state, retry: load };
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

  // Few stored days and a real catalog product: offer the one-time full history fetch.
  const canLoadHistory = productId.startsWith("tcgapi:") && !(series[0] && series[0].date <= addDays(today, -60));
  const full = useFullHistory(productId, printing, canLoadHistory);
  const first = sliced[0];
  const at = scrub !== null && sliced[scrub] ? sliced[scrub] : sliced[sliced.length - 1];
  const change = first && at ? at.price - first.price : null;
  const isSample = data.prices[key]?.source === "sample";

  const markers = useMemo<ChartMarker[]>(
    () =>
      effectiveTransactions(data.transactions)
        .filter((t) => t.productId === productId && (t.printing ?? null) === (printing ?? null) && (t.type === "purchase" || t.type === "sale"))
        .map((t) => ({
          date: t.date,
          kind: t.type === "sale" ? "sell" : "buy",
          label: `${t.type === "sale" ? "Sold" : "Bought"} ${t.quantity} × ${money(t.unitPrice)}`,
        })),
    [data.transactions, productId, printing],
  );

  return (
    <Card className="mt-8 p-5 sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="font-display text-[18px] leading-none tracking-[-0.01em]">Market price history</h2>
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
        <ChipTiles ariaLabel="History range" size="sm" className="-mr-1 pr-1 [mask-image:none]" value={range} onChange={setRange} options={(["1M", "3M", "1Y", "ALL"] as HistRange[]).map((r) => ({ value: r, label: r === "ALL" ? "All" : r }))} />
      </div>
      <div className="mt-4">
        {sliced.length > 1 ? (
          <ScrubChart data={sliced.map((p) => ({ date: p.date, value: p.price }))} tone={tone(sliced[sliced.length - 1].price - sliced[0].price)} baseline={sliced[0].price} onScrub={setScrub} height={220} markers={markers} />
        ) : (
          <div className="flex h-[220px] flex-col items-center justify-center rounded-2xl border border-dashed border-border px-6 text-center text-[13px] text-muted">
            {full.status === "loading" ? (
              <p className="flex items-center gap-2 font-medium text-foreground">
                <Loader2 className="size-4 animate-spin" /> Loading price history…
              </p>
            ) : (
              <>
                <p className="font-medium text-foreground">{full.note ?? "Not enough price history yet"}</p>
                <p className="mt-1 max-w-sm">
                  Corodex stores a daily snapshot for products you own or watch, so this chart fills in over time. Missing days are never filled with estimates.
                </p>
                {full.status === "error" && (
                  <Button variant="secondary" size="sm" className="mt-4" onClick={() => void full.retry()}>
                    Try again
                  </Button>
                )}
              </>
            )}
          </div>
        )}
      </div>
      <p className="mt-2 text-[11px] text-subtle">
        {markers.length > 0 && (
          <span className="mr-3 inline-flex items-center gap-1.5 text-muted">
            <span className="size-2 rounded-full bg-foreground" /> Your purchases
            {markers.some((m) => m.kind === "sell") && (
              <>
                <span className="ml-2 size-2 rounded-full bg-down" /> Sales
              </>
            )}
          </span>
        )}
        {isSample ? "Sample series for demonstration — not market data." : `${series.length} daily observation${series.length === 1 ? "" : "s"} · gaps are shown as-is, never interpolated`}
      </p>
      {full.status === "loading" && sliced.length > 1 && (
        <p className="mt-2 flex items-center gap-1.5 text-[12px] text-muted">
          <Loader2 className="size-3 animate-spin" /> Loading the full history…
        </p>
      )}
    </Card>
  );
}

type Category = "Singles" | "Sealed" | "Graded";
const CATEGORY_TINT: Record<Category, { tint: string; tag: string }> = {
  Singles: { tint: "tint-purple", tag: "tag-purple" },
  Sealed: { tint: "tint-blue", tag: "tag-blue" },
  Graded: { tint: "tint-lime", tag: "tag-lime" },
};

/**
 * Your position, right under the title (the app's): how many, what you paid, and how far up or
 * down (profit from sales only when you've sold some), in a panel tinted the kind's colour. Each
 * copy is one row that opens Your copy (HoldingSheet) for its actions.
 */
function Position({ product, holdings, realized }: { product: Product; holdings: HoldingView[]; realized: number }) {
  const [managing, setManaging] = useState<HoldingView | null>(null);
  const qty = holdings.reduce((s, h) => s + h.quantity, 0);
  const priced = holdings.filter((h) => h.value !== null);
  const value = priced.reduce((s, h) => s + (h.value ?? 0), 0);
  const cost = holdings.reduce((s, h) => s + h.costBasis, 0);
  const pricedCost = priced.reduce((s, h) => s + h.costBasis, 0);
  const gain = value - pricedCost;
  const kind: Category = holdings.every((h) => h.identity.grade) ? "Graded" : product.kind === "sealed" ? "Sealed" : "Singles";
  const gainTone = tone(gain) === "up" ? "text-up" : tone(gain) === "down" ? "text-down" : "";
  return (
    <section className={cn("tint mt-6 rounded-[20px] p-5", CATEGORY_TINT[kind].tint)}>
      <div className="mb-4 flex items-center gap-2.5">
        <h2 className="font-display text-[22px] leading-none tracking-[-0.02em]">Your position</h2>
        <span className={cn("tag-skew", CATEGORY_TINT[kind].tag)}>{kind}</span>
      </div>
      <dl className="flex flex-wrap gap-x-6 gap-y-4">
        <Stat label="You own" value={`×${qty}`} />
        <Stat label="Paid" value={money(cost)} />
        <Stat label={gain >= 0 ? "Up" : "Down"} value={<span className={gainTone}>{money(Math.abs(gain))}{pricedCost > 0 ? ` (${signedPct(gain / pricedCost)})` : ""}</span>} />
        {realized !== 0 && <Stat label="From sales" value={<Delta value={realized} />} />}
      </dl>
      <div className="mt-6 divide-y divide-border border-t border-border">
        {holdings.map((h) => (
          <button key={h.key} type="button" onClick={() => setManaging(h)} className="group flex w-full items-center gap-3 pt-3.5 text-left [&:not(:last-child)]:pb-3.5">
            <div className="min-w-0 flex-1">
              <p className="truncate text-[14px] font-medium">
                {h.quantity} × {holdingLabel(h) ?? (product.kind === "sealed" ? "Sealed" : h.identity.condition)}
              </p>
              <p className="tabular text-[12px] text-muted">
                {h.lots.length} open lot{h.lots.length === 1 ? "" : "s"} · avg {money(h.avgCost)}
              </p>
            </div>
            <span className="flex items-center gap-1.5">
              <Delta value={h.unrealized} className="text-[13px]" />
              <DeltaPill ratio={h.unrealizedPct} className="text-[11px]" />
            </span>
            <MoreHorizontal aria-label="Actions" className="size-4 shrink-0 text-muted transition-colors group-hover:text-foreground" />
          </button>
        ))}
      </div>
      <HoldingSheet holding={managing} onOpenChange={(o) => !o && setManaging(null)} hideViewDetails />
    </section>
  );
}

/** For each graded copy you own: its cert number (with a lookup link) and its bumper. */
function YourSlabs({ holdings }: { holdings: HoldingView[] }) {
  return (
    <section className="mt-6">
      <h2 className="mb-3.5 font-display text-[22px] leading-none tracking-[-0.02em]">{holdings.length === 1 ? "Your slab" : "Your slabs"}</h2>
      <div className="space-y-3.5">
        {holdings.map((h) => (
          <SlabPanel key={h.key} h={h} label={holdings.length > 1} />
        ))}
      </div>
    </section>
  );
}

function SlabPanel({ h, label }: { h: HoldingView; label: boolean }) {
  const { certs } = useSlabCerts();
  const { bumpers } = useSlabBumpers();
  const [open, setOpen] = useState<"cert" | "bumper" | null>(null);
  const grade = h.identity.grade!;
  const cert = certs[h.key];
  const bumper = bumperById(bumpers[h.key]);
  const dark = "inline-flex h-9 items-center gap-1.5 rounded-xl bg-surface-2 px-3.5 text-[14px] font-semibold ring-1 ring-inset ring-border transition-colors hover:bg-surface-3";
  return (
    <Card className="p-4">
      {label && <p className="mb-2.5 font-mono text-[11px] font-medium uppercase tracking-[0.06em] text-subtle">{gradeLabel(grade)}</p>}
      <div className="flex items-center gap-2.5">
        <div className="min-w-0 flex-1">
          <p className="text-[12px] text-muted">Cert number</p>
          <p className={cn("mt-0.5 truncate font-mono text-[15px] font-medium", !cert && "text-subtle")}>{cert ?? "Not added"}</p>
        </div>
        {cert && (
          <a href={certLookupUrl(grade.company, cert)} target="_blank" rel="noreferrer" className={dark}>
            <ExternalLink className="size-4" /> Look up
          </a>
        )}
        <button type="button" onClick={() => setOpen("cert")} className={dark}>
          {cert ? "Edit" : "Add"}
        </button>
      </div>
      <div className="my-2.5 h-px bg-border" />
      <button type="button" onClick={() => setOpen("bumper")} className="flex w-full items-center gap-2.5 text-left">
        <span className="flex size-[22px] shrink-0 items-center justify-center rounded-full ring-1 ring-inset ring-white/20" style={{ background: bumper?.background ?? "transparent" }}>
          {!bumper && <Plus className="size-2.5 text-muted" strokeWidth={3} />}
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-[12px] text-muted">Bumper</span>
          <span className="block truncate text-[15px] font-medium">{bumper?.name ?? "Add a bumper"}</span>
        </span>
        <ChevronRight className="size-3.5 shrink-0 text-subtle" strokeWidth={3} />
      </button>
      <CertDialog holding={h} open={open === "cert"} onOpenChange={(o) => !o && setOpen(null)} />
      <BumperDialog h={h} open={open === "bumper"} onOpenChange={(o) => !o && setOpen(null)} />
    </Card>
  );
}

function History({ productId }: { productId: string }) {
  const { data } = useStore();
  const [showHidden, setShowHidden] = useState(false);
  const all = data.transactions.filter((t) => t.productId === productId);
  if (!all.length) return null;
  const { effective, visible, hidden } = partitionHistory(all);
  const byNewest = (a: Transaction, b: Transaction) => (a.date === b.date ? (a.createdAt < b.createdAt ? 1 : -1) : a.date < b.date ? 1 : -1);
  const rows = [...visible].sort(byNewest);
  const hiddenRows = [...hidden].sort(byNewest);
  const notes = visible.map((t) => effective.get(t.id) ?? t).filter((t) => t.notes);

  return (
    <>
      <Card className="mt-6 p-5 sm:p-6">
        <SectionTitle title="Purchase history" />
        {rows.length ? (
          <ul className="divide-y divide-border">
            {rows.map((t) => {
              const shown = effective.get(t.id) ?? t;
              const edited = shown.unitPrice !== t.unitPrice || shown.quantity !== t.quantity || shown.date !== t.date || shown.fees !== t.fees || shown.shipping !== t.shipping || shown.tax !== t.tax;
              const amount = t.type === "sale" ? saleProceeds(shown) : acquisitionCost(shown);
              return (
                <li key={t.id} className="flex items-center gap-3 py-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-[14px] font-medium capitalize">
                      {t.type === "adjustment" ? (t.quantity > 0 ? "Added" : "Removed") : t.type}
                      <span className="tabular font-normal text-muted">
                        {" "}
                        · {Math.abs(shown.quantity)} × {money(shown.unitPrice)}
                      </span>
                      {edited && <Badge className="ml-2 normal-case">Edited</Badge>}
                    </p>
                    <p className="truncate text-[12px] text-muted">
                      {formatDate(shown.date)}
                      {shown.source && ` · ${shown.source}`}
                    </p>
                  </div>
                  <span className="tabular text-[14px]">
                    {t.type === "sale" ? "+" : ""}
                    {money(amount)}
                  </span>
                  <TransactionActions tx={t} />
                </li>
              );
            })}
          </ul>
        ) : (
          <p className="py-2 text-[14px] text-muted">No active entries.</p>
        )}
        {hiddenRows.length > 0 && (
          <div className="mt-3 border-t border-border pt-3">
            <button onClick={() => setShowHidden((v) => !v)} className="text-[12px] font-medium text-subtle hover:text-muted">
              {showHidden ? "Hide" : "Show"} deleted &amp; edit records ({hiddenRows.length})
            </button>
            {showHidden && (
              <ul className="mt-2 space-y-1.5">
                {hiddenRows.map((t) => (
                  <li key={t.id} className="tabular text-[12px] text-subtle">
                    {t.type === "correction" ? `${t.quantity === 0 ? "Deleted" : "Edited"} an entry` : `${t.type === "adjustment" ? "Adjustment" : t.type[0].toUpperCase() + t.type.slice(1)} · ${Math.abs(t.quantity)} × ${money(t.unitPrice)} (deleted)`}
                    {" · "}
                    {formatDate(t.createdAt)}
                    {t.type === "correction" && t.notes && !["Deleted", "Edited", "Voided", "Corrected"].includes(t.notes) ? ` · ${t.notes}` : ""}
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
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
