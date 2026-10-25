"use client";

import { BookOpen, ChevronLeft, ChevronRight, Loader2, Plus } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useMemo, useState } from "react";
import { CompletionRing } from "@/components/binder/completion-ring";
import { HoloTilt } from "@/components/motion/holo-tilt";
import { Reveal } from "@/components/motion/reveal";
import { ErrorState } from "@/components/portfolio/error-state";
import { holdingLabel } from "@/components/portfolio/holding-items";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { ownedIn, ownedSets, useChecklist, type OwnedSet } from "@/lib/checklists";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money, pct } from "@/lib/format";
import type { ChecklistCard } from "@/lib/pricing/types";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import type { Product } from "@/lib/types";
import { cn } from "@/lib/utils";

const PER_PAGE = 9;
type Show = "all" | "owned" | "missing";

export default function BinderPage() {
  return (
    <Suspense fallback={<BinderSkeleton />}>
      <Binder />
    </Suspense>
  );
}

function Binder() {
  const store = useStore();
  const { holdings } = usePortfolio();
  const params = useSearchParams();
  const router = useRouter();
  const sets = useMemo(() => ownedSets(holdings), [holdings]);
  const selectedId = params.get("set") ?? sets[0]?.setId ?? null;
  const selected = sets.find((s) => s.setId === selectedId) ?? sets[0] ?? null;

  if (store.status === "loading") return <BinderSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  return (
    <div className="animate-fade-in">
      <PageHeader title="Binder" subtitle="Your singles, page by page — and what's missing from each set" />
      {!sets.length ? (
        <div className="flex flex-col items-center py-24 text-center">
          <BookOpen className="size-10 text-subtle" strokeWidth={1.5} />
          <p className="mt-4 font-medium">No singles yet</p>
          <p className="mt-1 max-w-sm text-sm text-muted">Add a single card and its set appears here as a binder, with empty pockets for the cards you don&apos;t own yet.</p>
          <Button variant="primary" className="mt-6" onClick={() => store.openAdd()}>
            <Plus /> Add a card
          </Button>
        </div>
      ) : (
        <>
          <section aria-label="Set completion" className="scrollbar-none -mx-4 flex snap-x scroll-px-4 gap-3 overflow-x-auto px-4 pb-2 sm:-mx-8 sm:scroll-px-8 sm:px-8">
            {sets.map((s) => (
              <SetTile key={s.setId} set={s} active={s.setId === selected?.setId} onSelect={() => router.replace(`/binder?set=${encodeURIComponent(s.setId)}`, { scroll: false })} />
            ))}
          </section>
          {selected && <BinderBook key={selected.setId} set={selected} />}
        </>
      )}
    </div>
  );
}

/* ---------------------------- Set tile + ring ---------------------------- */

function SetTile({ set, active, onSelect }: { set: OwnedSet; active: boolean; onSelect: () => void }) {
  const { checklist, loading } = useChecklist(set);
  const owned = checklist ? ownedIn(checklist, set).size : set.holdings.length;
  const total = checklist?.cards.length ?? null;
  const ratio = total ? owned / total : null;
  return (
    <button
      onClick={onSelect}
      aria-pressed={active}
      className={cn(
        "flex w-[230px] shrink-0 snap-start items-center gap-4 rounded-[var(--radius-card)] border p-4 text-left transition-colors",
        active ? "border-border-strong bg-surface-2" : "border-border bg-surface hover:bg-surface-2/60",
      )}
    >
      <CompletionRing value={ratio} size={58} stroke={5}>
        {loading ? <Loader2 className="size-4 animate-spin text-subtle" /> : <span className="tabular text-[12px] font-semibold">{ratio === null ? "—" : pct(ratio, 0)}</span>}
      </CompletionRing>
      <div className="min-w-0">
        <p className="truncate text-[14px] font-semibold">{set.name}</p>
        <p className="tabular mt-0.5 text-[12px] text-muted">
          {owned} / {total ?? "?"} cards
        </p>
        {ratio !== null && ratio >= 1 && <p className="mt-0.5 text-[11px] font-semibold text-up">Complete</p>}
      </div>
    </button>
  );
}

/* --------------------------------- Book ---------------------------------- */

interface Slot {
  card: ChecklistCard;
  holdings: HoldingView[];
}

function useSpread() {
  const [wide, setWide] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(min-width: 1024px)");
    const on = () => setWide(mq.matches);
    on();
    mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, []);
  return wide ? 2 : 1;
}

function BinderBook({ set }: { set: OwnedSet }) {
  const { checklist, loading, error, sample } = useChecklist(set);
  const { openAdd } = useStore();
  const [show, setShow] = useState<Show>("all");
  const [page, setPage] = useState(0);
  const [dir, setDir] = useState<"next" | "prev">("next");
  const pagesPerView = useSpread();

  const slots: Slot[] = useMemo(() => {
    const byProduct = new Map<string, HoldingView[]>();
    for (const h of set.holdings) byProduct.set(h.identity.productId, [...(byProduct.get(h.identity.productId) ?? []), h]);
    if (!checklist) {
      // No checklist (API unavailable): show only what's owned.
      return [...byProduct.values()].map((hs) => ({
        card: { productId: hs[0].identity.productId, number: hs[0].product?.number ?? null, name: hs[0].product?.name ?? "", rarity: null, imageUrl: hs[0].product?.imageUrl ?? null, market: hs[0].price },
        holdings: hs,
      }));
    }
    const listed = checklist.cards.map((card) => ({ card, holdings: byProduct.get(card.productId) ?? [] }));
    // Owned cards the checklist doesn't list (e.g. promos) go at the end.
    const extra = [...byProduct.entries()].filter(([id]) => !checklist.cards.some((c) => c.productId === id));
    return [...listed, ...extra.map(([, hs]) => ({ card: { productId: hs[0].identity.productId, number: hs[0].product?.number ?? null, name: hs[0].product?.name ?? "", rarity: null, imageUrl: hs[0].product?.imageUrl ?? null, market: hs[0].price }, holdings: hs }))];
  }, [checklist, set.holdings]);

  const visible = useMemo(() => slots.filter((s) => (show === "owned" ? s.holdings.length : show === "missing" ? !s.holdings.length : true)), [slots, show]);
  const perView = PER_PAGE * pagesPerView;
  const views = Math.max(1, Math.ceil(visible.length / perView));
  const current = Math.min(page, views - 1);
  const pageSlots = visible.slice(current * perView, current * perView + perView);

  const missing = slots.filter((s) => !s.holdings.length);
  const missingPriced = missing.filter((s) => s.card.market !== null);
  const toComplete = missingPriced.reduce((sum, s) => sum + (s.card.market ?? 0), 0);
  const ownedCount = slots.length - missing.length;

  // Open on the first page that holds a card you own.
  const [opened, setOpened] = useState(false);
  useEffect(() => {
    if (opened || loading || (!checklist && !error) || !visible.length) return;
    const first = visible.findIndex((s) => s.holdings.length);
    if (first > 0) setPage(Math.floor(first / perView));
    setOpened(true);
  }, [opened, loading, checklist, error, visible, perView]);

  const go = (d: 1 | -1) => {
    setOpened(true);
    setDir(d === 1 ? "next" : "prev");
    setPage((p) => Math.max(0, Math.min(views - 1, Math.min(p, views - 1) + d)));
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement)?.closest("input, textarea, [role=dialog]")) return;
      if (e.key === "ArrowRight") go(1);
      if (e.key === "ArrowLeft") go(-1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const addMissing = (card: ChecklistCard) => {
    const product: Product = {
      id: card.productId,
      source: "tcgapi",
      externalId: card.productId.replace(/^tcgapi:/, ""),
      name: card.name,
      setName: checklist?.name ?? set.name,
      setId: set.setId,
      number: card.number,
      rarity: card.rarity,
      productType: "Cards",
      kind: "single",
      imageUrl: card.imageUrl,
      tcgplayerId: null,
      tcgplayerUrl: null,
    };
    openAdd({ hit: { product, printing: null, market: card.market, priceUpdatedAt: null } });
  };

  return (
    <div className="mt-8">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h2 className="text-[22px] font-semibold tracking-[-0.01em]">{checklist?.name ?? set.name}</h2>
          <p className="tabular mt-1 text-[13px] text-muted">
            {ownedCount} of {checklist ? slots.length : "?"} collected
            {checklist && missingPriced.length > 0 && !sample && (
              <>
                {" "}
                · complete it for about <span className="font-medium text-foreground">{money(toComplete)}</span>
              </>
            )}
            {sample && (
              <Badge variant="sample" className="ml-2">
                Sample checklist
              </Badge>
            )}
          </p>
        </div>
        <Segmented
          ariaLabel="Show"
          size="sm"
          value={show}
          onChange={(v) => {
            setShow(v);
            setPage(0);
          }}
          options={[
            { value: "all", label: "All" },
            { value: "owned", label: "Owned" },
            { value: "missing", label: "Missing" },
          ]}
        />
      </div>

      {error && <p className="mt-3 rounded-xl bg-surface px-4 py-3 text-[13px] text-muted">Couldn&apos;t load the full checklist ({error}). Showing the cards you own.</p>}

      <div className="relative mt-5 rounded-[1.75rem] border border-border bg-[linear-gradient(180deg,var(--surface),color-mix(in_srgb,var(--surface)_70%,black))] p-3 shadow-2xl shadow-black/30 sm:p-5">
        {loading ? (
          <div className="grid grid-cols-3 gap-2.5 sm:gap-3 lg:grid-cols-6">
            {Array.from({ length: perView }).map((_, i) => (
              <Skeleton key={i} className="aspect-[63/88] rounded-xl" />
            ))}
          </div>
        ) : (
          <div key={`${show}-${current}`} className={cn("grid gap-4 lg:grid-cols-2 lg:gap-0", dir === "next" ? "animate-page-next" : "animate-page-prev")}>
            {Array.from({ length: pagesPerView }).map((_, p) => {
              const chunk = pageSlots.slice(p * PER_PAGE, p * PER_PAGE + PER_PAGE);
              return (
                <div key={p} className={cn("grid grid-cols-3 content-start gap-2.5 sm:gap-3", pagesPerView === 2 && (p === 0 ? "lg:border-r lg:border-dashed lg:border-border lg:pr-5" : "lg:pl-5"))}>
                  {Array.from({ length: PER_PAGE }).map((_, i) => {
                    const slot = chunk[i];
                    if (!slot) return <div key={i} className="aspect-[63/88] rounded-xl border border-dashed border-border/50" />;
                    return slot.holdings.length ? (
                      <OwnedPocket key={slot.card.productId} slot={slot} />
                    ) : (
                      <EmptyPocket key={slot.card.productId} card={slot.card} sample={sample} onAdd={() => addMissing(slot.card)} />
                    );
                  })}
                </div>
              );
            })}
          </div>
        )}

        <div className="mt-4 flex items-center justify-between">
          <Button variant="ghost" size="sm" onClick={() => go(-1)} disabled={current === 0} aria-label="Previous page">
            <ChevronLeft /> Prev
          </Button>
          <p className="tabular text-[12px] text-muted">
            {pagesPerView === 2 ? `Pages ${current * 2 + 1}–${current * 2 + 2}` : `Page ${current + 1}`} of {Math.max(1, Math.ceil(visible.length / PER_PAGE))}
          </p>
          <Button variant="ghost" size="sm" onClick={() => go(1)} disabled={current >= views - 1} aria-label="Next page">
            Next <ChevronRight />
          </Button>
        </div>
      </div>

      {checklist && !sample && missingPriced.length > 0 && (
        <Reveal as="section" className="mt-10">
          <h3 className="text-[17px] font-semibold">Most valuable missing cards</h3>
          <p className="mt-0.5 text-[13px] text-muted">What it would take to finish {checklist.name}</p>
          <div className="mt-4 grid gap-2 sm:grid-cols-2">
            {[...missingPriced]
              .sort((a, b) => (b.card.market ?? 0) - (a.card.market ?? 0))
              .slice(0, 8)
              .map(({ card }) => (
                <button key={card.productId} onClick={() => addMissing(card)} className="group flex items-center gap-3 rounded-2xl bg-surface p-2.5 text-left transition-colors hover:bg-surface-2">
                  <ProductImage product={{ name: card.name, imageUrl: card.imageUrl, kind: "single", setName: checklist.name, productType: "Cards" }} size="xs" className="h-14 w-10 shrink-0 rounded-md" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[14px] font-medium">{card.name}</p>
                    <p className="truncate text-[12px] text-muted">{[card.number && `#${card.number}`, card.rarity].filter(Boolean).join(" · ")}</p>
                  </div>
                  <span className="tabular text-[14px] font-semibold">{money(card.market)}</span>
                  <Plus className="size-4 text-subtle transition-colors group-hover:text-foreground" />
                </button>
              ))}
          </div>
        </Reveal>
      )}
    </div>
  );
}

function OwnedPocket({ slot }: { slot: Slot }) {
  const h = slot.holdings[0];
  const qty = slot.holdings.reduce((s, x) => s + x.quantity, 0);
  return (
    <Link href={`/product/${encodeURIComponent(slot.card.productId)}`} className="group relative block" title={slot.card.name}>
      <HoloTilt max={10} radius="0.75rem" className="aspect-[63/88] w-full">
        <ProductImage product={h.product} size="sm" className="h-full w-full rounded-xl ring-1 ring-white/10" />
      </HoloTilt>
      {qty > 1 && <span className="tabular absolute right-1.5 top-1.5 rounded-full bg-background/85 px-1.5 text-[10px] font-semibold backdrop-blur">×{qty}</span>}
      {holdingLabel(h) && <span className="absolute bottom-1.5 left-1.5 rounded-full bg-background/85 px-1.5 text-[10px] font-medium backdrop-blur">{holdingLabel(h)}</span>}
    </Link>
  );
}

function EmptyPocket({ card, sample, onAdd }: { card: ChecklistCard; sample: boolean; onAdd: () => void }) {
  const inner = (
    <>
      {card.imageUrl && (
        // eslint-disable-next-line @next/next/no-img-element -- ghosted catalog image
        <img src={card.imageUrl} alt="" loading="lazy" className="absolute inset-0 h-full w-full rounded-xl object-contain p-1 opacity-[0.12] grayscale transition-opacity group-hover:opacity-30" />
      )}
      <span className="tabular relative text-[11px] font-semibold text-subtle">#{card.number ?? "—"}</span>
      {!sample && <span className="relative mt-1 line-clamp-2 px-2 text-center text-[10px] leading-tight text-subtle">{card.name}</span>}
      {!sample && card.market !== null && <span className="tabular relative mt-1 text-[10px] text-muted">{money(card.market)}</span>}
      {!sample && <Plus className="relative mt-1.5 size-3.5 text-subtle opacity-0 transition-opacity group-hover:opacity-100" />}
    </>
  );
  const cls = "group relative flex aspect-[63/88] w-full flex-col items-center justify-center overflow-hidden rounded-xl border border-dashed border-border-strong/60 bg-background/40";
  return sample ? (
    <div className={cls}>{inner}</div>
  ) : (
    <button onClick={onAdd} className={cn(cls, "transition-colors hover:border-foreground/30 hover:bg-surface-2/50")} aria-label={`Add ${card.name}`}>
      {inner}
    </button>
  );
}

function BinderSkeleton() {
  return (
    <div aria-busy="true">
      <Skeleton className="h-9 w-40" />
      <div className="mt-8 flex gap-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-[90px] w-[230px] rounded-2xl" />
        ))}
      </div>
      <Skeleton className="mt-8 h-[520px] w-full rounded-[1.75rem]" />
    </div>
  );
}
