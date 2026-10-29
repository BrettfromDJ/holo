"use client";

import { useHeroTarget } from "@/lib/motion/hero";
import { Hint } from "@/components/ui/tooltip";
import { WishButton } from "@/components/wishlist/wish-items";
import { BumperButton, CertDialog, GradeChip, SendToGraderDialog, SlabCard, useAtGrader } from "@/components/grading/grading-items";
import { Calculator, Check, ChevronDown, ChevronLeft, ExternalLink, Eye, EyeOff, Layers, Loader2, MoreHorizontal, Package, Plus, Tag } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { ScrubChart, type ChartMarker } from "@/components/charts/scrub-chart";
import { SellCalculatorDialog } from "@/components/flows/sell-calculator";
import { AdjustDialog, ManualValueDialog, SaleDialog, TransactionActions, partitionHistory } from "@/components/flows/transaction-dialogs";
import { ErrorState } from "@/components/portfolio/error-state";
import { holdingLabel } from "@/components/portfolio/holding-items";
import { Delta, DeltaPill } from "@/components/product/delta";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { Reveal } from "@/components/motion/reveal";
import { HoloTilt, isFoilCard } from "@/components/motion/holo-tilt";
import { MoveToPortfolio } from "@/components/portfolio/portfolio-controls";
import { ShelfMenu } from "@/components/shelves/shelf-controls";
import { ProductImage } from "@/components/product/product-image";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, SectionTitle } from "@/components/ui/card";
import { EbaySales } from "@/components/product/ebay-sales";
import { WhatsItWorth } from "@/components/product/whats-it-worth";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { categoryOf } from "@/lib/catalog";
import { packCount, pricePerPack } from "@/lib/packs";
import { addDays } from "@/lib/finance/dates";
import { acquisitionCost, effectiveTransactions, saleProceeds } from "@/lib/finance/ledger";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, relativeTime, tone } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { priceKey, type Product, type Transaction } from "@/lib/types";

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

  if (store.status === "loading" || (!product && loading)) return <ProductSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!product) return <ErrorState message={loadError ?? "This product couldn't be found."} />;

  const owned = holdings.filter((h) => h.identity.productId === productId);
  const realizedHere = realized.filter((r) => r.holdingKey.startsWith(`${productId}|`)).reduce((s, r) => s + r.gain, 0);
  const printing = owned[0]?.identity.printing ?? product.printings?.[0] ?? null;
  const price = store.data.prices[priceKey(productId, printing)];
  const watch = store.data.watchlist.find((w) => w.productId === productId);
  const slab = owned.length > 0 && owned.every((h) => h.identity.grade) ? owned[0].identity.grade : null;

  return (
    <div className="animate-fade-in">
      {/* Owned products go back to the collection; catalog products back to their set in Explore. */}
      {owned.length || !product.setId || product.source !== "tcgapi" ? (
        <Link href="/collection" className="mb-6 inline-flex items-center gap-1 text-[14px] text-muted hover:text-foreground">
          <ChevronLeft className="size-4" /> Collection
        </Link>
      ) : (
        <Link href={`/explore/${encodeURIComponent(product.setId)}`} className="mb-6 inline-flex items-center gap-1 text-[14px] text-muted hover:text-foreground">
          <ChevronLeft className="size-4" /> {product.setName ?? "Explore"}
        </Link>
      )}

      <div className="grid gap-8 lg:grid-cols-[minmax(0,420px)_1fr] lg:gap-12">
        {slab ? (
          // Only slabs of this card are owned: show it in its slab.
          <div className="flex flex-col items-center self-start lg:sticky lg:top-10">
            <HoloTilt heroName={hero.name} radius="7% / 4.4%" foil={false} className={`mx-auto aspect-[5/8] w-full max-w-[260px] ${hero.arriving ? "" : "animate-pop"} sm:max-w-[340px]`}>
              <ProductImage product={product} grade={slab} slabKey={owned[0]?.key} size="xl" priority className="h-full w-full" />
            </HoloTilt>
            <BumperButton h={owned[0]} className="mt-6 py-1.5 pl-1.5 pr-3.5 text-[13px]" />
          </div>
        ) : product.kind === "single" && product.imageUrl ? (
          // A bare card: no well or frame, just the card at its own proportions.
          <HoloTilt heroName={hero.name} radius="4.5% / 3.2%" foil={isFoilCard(product)} className={`mx-auto aspect-[63/88] w-full max-w-[260px] ${hero.arriving ? "" : "animate-pop"} sm:max-w-[360px] self-start lg:sticky lg:top-10`}>
            <ProductImage product={product} size="xl" priority frame={false} className="h-full w-full rounded-[4.5%/3.2%] shadow-2xl shadow-black/50" />
          </HoloTilt>
        ) : (
          <HoloTilt heroName={hero.name} radius="1.75rem" foil={false} className={`aspect-square w-full ${hero.arriving ? "" : "animate-pop"} lg:sticky lg:top-10`}>
            <ProductImage product={product} size="xl" priority className="h-full w-full rounded-[1.75rem]" />
          </HoloTilt>
        )}

        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <KindMenu productId={productId} kind={product.kind} label={categoryOf(product)} />
            {product.rarity && <Badge variant="outline">{product.rarity}</Badge>}
            {product.source === "sample" && <Badge variant="sample">Sample data</Badge>}
          </div>
          <h1 className="mt-3 font-display text-[34px] uppercase leading-[0.98] tracking-[0.005em] sm:text-[48px]">{product.name}</h1>
          <p className="mt-1 text-[15px] text-muted">
            {[product.setName, product.number ? `#${product.number}` : null, printing && printing !== "Normal" ? printing : null].filter(Boolean).join(" · ")}
          </p>

          <div className="mt-6">
            <p className="tabular font-display text-[52px] leading-none sm:text-[60px]">
              {price?.market != null ? <AnimatedNumber key={productId} value={price.market} format={money} from={price.market * 0.85} /> : <span className="text-muted">No price</span>}
            </p>
            {product.kind === "sealed" && <PerPack product={product} price={price?.market ?? null} />}
            {owned.some((h) => h.identity.grade) && (
              <div className="mt-2 flex flex-wrap items-center gap-x-1.5 gap-y-1 text-[13px] text-muted">
                <span>Ungraded price.</span>
                {owned
                  .filter((h) => h.identity.grade && h.price !== null)
                  .map((h) => (
                    <span key={h.key} className="inline-flex items-center gap-1.5">
                      Your <GradeChip grade={h.identity.grade!} /> <span className="tabular text-foreground">{money(h.price)}</span>
                    </span>
                  ))}
              </div>
            )}
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

          <div className="mt-6 flex flex-wrap gap-1.5 sm:gap-2 max-sm:[&_button.size-10]:size-9 max-sm:[&_a.size-10]:size-9">
            <Button variant="primary" onClick={() => store.openAdd({ productId })}>
              <Plus /> {owned.length ? "Add more" : "Add to collection"}
            </Button>
            {owned.length > 0 && <SaleButton holdings={owned} />}
            <WatchButton productId={productId} printing={printing} watchId={watch?.id} />
            <WishButton product={product} price={price?.market ?? null} printing={printing} compact />
            <ShelfMenu productId={productId} compact />
            {product.tcgplayerUrl && (
              <Hint content="View on TCGplayer">
                <Button variant="ghost" size="icon" asChild>
                  <a href={product.tcgplayerUrl} target="_blank" rel="noreferrer" aria-label="View on TCGplayer">
                    <ExternalLink />
                  </a>
                </Button>
              </Hint>
            )}
          </div>

          <Reveal delay={80}>
            <PriceHistory productId={productId} printing={printing} />
          </Reveal>

          {(product.source === "tcgapi" || product.source === "sample") && (
            <Reveal>
              <EbaySales productId={productId} printing={printing} grade={owned.find((h) => h.identity.grade)?.identity.grade ?? null} className="mt-6" />
            </Reveal>
          )}

          {/* What's it worth in any condition or grade; the full graded table opens from inside it. */}
          {product.kind === "single" && (
            <Reveal>
              <WhatsItWorth productId={productId} printing={printing} name={product.name} nm={price?.market ?? null} owned={owned} />
            </Reveal>
          )}

          {owned.length > 0 && (
            <Reveal>
              <Position holdings={owned} realized={realizedHere} />
            </Reveal>
          )}
          {owned.length === 0 && realizedHere !== 0 && (
            <Card className="mt-6 p-5">
              <p className="text-[13px] text-muted">Position closed · realized</p>
              <Delta value={realizedHere} className="mt-1 text-[20px] font-semibold" />
            </Card>
          )}
          <Reveal>
            <History productId={productId} />
          </Reveal>
        </div>
      </div>
    </div>
  );
}

/** Category badge that doubles as a "Change type" control (sealed ⇄ single). */
function KindMenu({ productId, kind, label }: { productId: string; kind: Product["kind"]; label: string }) {
  const { setProductKind } = useStore();
  const change = async (next: Product["kind"]) => {
    if (next === kind) return;
    try {
      await setProductKind(productId, next);
      toast.success(next === "sealed" ? "Marked as sealed product" : "Marked as single card");
    } catch (e) {
      toast.error((e as Error).message);
    }
  };
  return (
    <DropdownMenu>
      <DropdownMenuTrigger className="inline-flex items-center gap-1 rounded-full bg-surface-2 px-2 py-0.5 text-[11px] font-medium leading-4 text-muted transition-colors hover:bg-surface-3 hover:text-foreground" aria-label={`Type: ${label}. Change type`}>
        {label}
        <ChevronDown className="size-3" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuLabel>Product type</DropdownMenuLabel>
        <DropdownMenuItem onSelect={() => void change("sealed")}>
          <Package /> Sealed product {kind === "sealed" && <Check className="ml-auto !text-foreground" />}
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={() => void change("single")}>
          <Layers /> Single card {kind === "single" && <Check className="ml-auto !text-foreground" />}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/**
 * What if I sell? and Record sale, up top. With more than one version held
 * (say a raw copy and a PSA 10), each button first asks which one.
 */
function SaleButton({ holdings }: { holdings: HoldingView[] }) {
  const [open, setOpen] = useState<{ kind: "sale" | "whatif"; key: string } | null>(null);
  const target = holdings.find((h) => h.key === open?.key) ?? null;
  const action = (kind: "sale" | "whatif", label: string, icon: React.ReactNode) =>
    holdings.length === 1 ? (
      <Hint content={label}>
        <Button variant="secondary" size="icon" aria-label={label} onClick={() => setOpen({ kind, key: holdings[0].key })}>
          {icon}
        </Button>
      </Hint>
    ) : (
      <DropdownMenu>
        <Hint content={label}>
          <DropdownMenuTrigger asChild>
            <Button variant="secondary" size="icon" aria-label={label}>
              {icon}
            </Button>
          </DropdownMenuTrigger>
        </Hint>
        <DropdownMenuContent align="start">
          <DropdownMenuLabel>{label}</DropdownMenuLabel>
          {holdings.map((h) => (
            <DropdownMenuItem key={h.key} onSelect={() => setOpen({ kind, key: h.key })}>
              <span className="flex-1">{h.identity.grade ? `${h.identity.grade.company} ${h.identity.grade.grade}` : (holdingLabel(h) ?? h.identity.condition)}</span>
              <span className="tabular text-muted">× {h.quantity}</span>
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
    );
  return (
    <>
      {action("whatif", "What if I sell?", <Calculator />)}
      {action("sale", "Record sale", <Tag />)}
      {target && <SellCalculatorDialog holding={target} open={open?.kind === "whatif"} onOpenChange={(o) => !o && setOpen(null)} />}
      {target && <SaleDialog holding={target} open={open?.kind === "sale"} onOpenChange={(o) => !o && setOpen(null)} />}
    </>
  );
}

function WatchButton({ productId, printing, watchId }: { productId: string; printing: string | null; watchId?: string }) {
  const { addWatch, removeWatch } = useStore();
  const [busy, setBusy] = useState(false);
  return (
    <Hint content={watchId ? "Watching · tap to stop" : "Watch"}>
    <Button
      variant="secondary"
      size="icon"
      aria-label={watchId ? "Stop watching" : "Watch"}
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
    </Button>
    </Hint>
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

/** Fetch a product's full price history once (one TCG API request, then stored for everyone). */
function LoadHistoryButton({ productId, printing }: { productId: string; printing: string | null }) {
  const { mergeHistory } = useStore();
  const [state, setState] = useState<"idle" | "loading" | "done">("idle");
  return (
    <Button
      variant="secondary"
      size="sm"
      disabled={state !== "idle"}
      onClick={async () => {
        setState("loading");
        try {
          const res = await fetch(`/api/explore/products/${encodeURIComponent(productId)}/history`, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ printing }),
          });
          const body = await res.json().catch(() => null);
          if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't load price history.");
          mergeHistory(productId, printing, body.points ?? []);
          if (!body.available) toast(body.reason ?? "Your TCG API plan doesn't include price history.");
          else if (!body.points?.length) toast("No price history is available for this product.");
          setState("done");
        } catch (e) {
          toast.error((e as Error).message);
          setState("idle");
        }
      }}
    >
      {state === "loading" ? <Loader2 className="animate-spin" /> : null}
      {state === "done" ? "History loaded" : "Load full price history"}
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

  // Few stored days and a real catalog product: offer the one-time full history fetch.
  const canLoadHistory = productId.startsWith("tcgapi:") && !(series[0] && series[0].date <= addDays(today, -60));
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
          <ScrubChart data={sliced.map((p) => ({ date: p.date, value: p.price }))} tone={tone(sliced[sliced.length - 1].price - sliced[0].price)} baseline={sliced[0].price} onScrub={setScrub} height={220} markers={markers} />
        ) : (
          <div className="flex h-[220px] flex-col items-center justify-center rounded-2xl border border-dashed border-border px-6 text-center text-[13px] text-muted">
            <p className="font-medium text-foreground">Not enough price history yet</p>
            <p className="mt-1 max-w-sm">
              Holo stores a daily snapshot for products you own or watch, so this chart fills in over time. Missing days are never filled with estimates.
            </p>
            {canLoadHistory && (
              <div className="mt-4">
                <LoadHistoryButton productId={productId} printing={printing} />
              </div>
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
      {canLoadHistory && sliced.length > 1 && (
        <div className="mt-3">
          <LoadHistoryButton productId={productId} printing={printing} />
        </div>
      )}
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
          <HoldingLine key={h.key} h={h} showBumper={holdings.length > 1} />
        ))}
      </div>
    </Card>
  );
}

function HoldingLine({ h, showBumper }: { h: HoldingView; showBumper: boolean }) {
  const [dialog, setDialog] = useState<"sale" | "whatif" | "adjust" | "value" | "cert" | "grade" | null>(null);
  const atGrader = useAtGrader().get(h.key) ?? 0;
  const gradeable = !h.identity.grade && h.product?.kind === "single";
  const menu = (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon-sm" aria-label="Holding actions">
          <MoreHorizontal />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onSelect={() => setDialog("whatif")}>What if I sell?</DropdownMenuItem>
        <DropdownMenuItem onSelect={() => setDialog("sale")}>Record sale</DropdownMenuItem>
        <DropdownMenuItem onSelect={() => setDialog("adjust")}>Adjust quantity</DropdownMenuItem>
        {h.identity.grade && <DropdownMenuItem onSelect={() => setDialog("value")}>Set your own value</DropdownMenuItem>}
        {h.identity.grade && <DropdownMenuItem onSelect={() => setDialog("cert")}>Cert number</DropdownMenuItem>}
        {gradeable && <DropdownMenuItem onSelect={() => setDialog("grade")}>Send for grading</DropdownMenuItem>}
      </DropdownMenuContent>
    </DropdownMenu>
  );
  return (
    <div className={h.identity.grade ? "py-4" : "flex items-center gap-3 py-3.5"}>
      {h.identity.grade ? (
        <SlabCard h={h} showBumper={showBumper} actions={<><MoveToPortfolio holdingKey={h.key} />{menu}</>} onRevalue={() => setDialog("value")} onCert={() => setDialog("cert")} />
      ) : (
        <>
          <div className="min-w-0 flex-1">
            <p className="flex flex-wrap items-center gap-2 text-[14px] font-medium">
              {h.quantity} × {holdingLabel(h) ?? h.identity.condition}
              {atGrader > 0 && <span className="rounded-full bg-surface-2 px-2 py-0.5 text-[11px] font-medium text-muted">{atGrader} at the grader</span>}
            </p>
            <p className="tabular text-[12px] text-muted">
              {h.lots.length} open lot{h.lots.length === 1 ? "" : "s"} · avg {money(h.avgCost)}
            </p>
          </div>
          <MoveToPortfolio holdingKey={h.key} />
          <Delta value={h.unrealized} ratio={h.unrealizedPct} className="text-[13px]" />
          {menu}
        </>
      )}
      <SellCalculatorDialog holding={h} open={dialog === "whatif"} onOpenChange={(o) => !o && setDialog(null)} />
      <SaleDialog holding={h} open={dialog === "sale"} onOpenChange={(o) => !o && setDialog(null)} />
      <AdjustDialog holding={h} open={dialog === "adjust"} onOpenChange={(o) => !o && setDialog(null)} />
      {h.identity.grade && <ManualValueDialog holding={h} open={dialog === "value"} onOpenChange={(o) => !o && setDialog(null)} />}
      {h.identity.grade && <CertDialog holding={h} open={dialog === "cert"} onOpenChange={(o) => !o && setDialog(null)} />}
      {gradeable && <SendToGraderDialog holding={h} open={dialog === "grade"} onOpenChange={(o) => !o && setDialog(null)} />}
    </div>
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
