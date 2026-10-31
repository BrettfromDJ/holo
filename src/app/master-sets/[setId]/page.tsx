"use client";

import { Check, ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useDeferredValue, useMemo, useState } from "react";
import { LimeChip, MASTER_SETS, SearchSort } from "@/components/master-sets/master-set-items";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { HoloTilt, isFoilCard } from "@/components/motion/holo-tilt";
import { ErrorState } from "@/components/portfolio/error-state";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { useChecklist, type OwnedSet } from "@/lib/checklists";
import { compareCollectorNumbers } from "@/lib/collector-number";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money } from "@/lib/format";
import { useHeroLink } from "@/lib/motion/hero";
import type { ChecklistCard } from "@/lib/pricing/types";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

type Show = "all" | "owned" | "missing";
type Sort = "number" | "priceHigh" | "priceLow" | "name" | "ownedFirst" | "missingFirst";

const SORTS: { value: Sort; label: string }[] = [
  { value: "number", label: "Set number" },
  { value: "priceHigh", label: "Price: high to low" },
  { value: "priceLow", label: "Price: low to high" },
  { value: "name", label: "Name" },
  { value: "ownedFirst", label: "Owned first" },
  { value: "missingFirst", label: "Missing first" },
];

/** One card of the set: the checklist entry, and your copies of it (none when missing). */
interface Entry {
  card: ChecklistCard;
  holdings: HoldingView[];
  /** A numbered placeholder in a demo set's sample checklist. */
  slot: boolean;
}

const owned = (e: Entry) => e.holdings.length > 0;
const priceOf = (e: Entry) => e.holdings[0]?.price ?? e.card.market;

function safeDecode(s: string) {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

function cardOf(hs: HoldingView[]): ChecklistCard {
  const p = hs[0].product;
  return { productId: hs[0].identity.productId, number: p?.number ?? null, name: p?.name ?? "", rarity: p?.rarity ?? null, imageUrl: p?.imageUrl ?? null, market: hs[0].price };
}

/** One master set: every card in it, the ones you own in full color, the rest dimmed, with your progress up top. */
export default function MasterSetPage() {
  const { setId: raw } = useParams<{ setId: string }>();
  const setId = safeDecode(raw);
  const store = useStore();
  const { holdings } = usePortfolio();

  const set: OwnedSet = useMemo(() => {
    const mine = holdings.filter((h) => h.product?.kind === "single" && h.product.setId === setId);
    return { setId, name: mine[0]?.product?.setName ?? setId, sample: mine.some((h) => h.product?.source === "sample"), holdings: mine };
  }, [holdings, setId]);
  const { checklist, loading: fetching, error, sample } = useChecklist(store.status === "ready" ? set : null);
  // Until the first load starts the state is empty; treat that as loading too.
  const loading = fetching || (!checklist && !error && !sample);

  const [show, setShow] = useState<Show>("all");
  const [sort, setSort] = useState<Sort>("number");
  const [query, setQuery] = useState("");
  const settledQuery = useDeferredValue(query);

  const entries: Entry[] = useMemo(() => {
    const byProduct = new Map<string, HoldingView[]>();
    for (const h of set.holdings) byProduct.set(h.identity.productId, [...(byProduct.get(h.identity.productId) ?? []), h]);
    const own = (hs: HoldingView[]): Entry => ({ card: cardOf(hs), holdings: hs, slot: false });
    if (!checklist) return [...byProduct.values()].map(own).sort((a, b) => compareCollectorNumbers(a.card.number, b.card.number));
    const listed = new Set(checklist.cards.map((c) => c.productId));
    // Owned cards the list doesn't include (promos) go at the end.
    return [
      ...checklist.cards.map((card) => ({ card, holdings: byProduct.get(card.productId) ?? [], slot: card.productId.startsWith("sample-slot:") })),
      ...[...byProduct.entries()].filter(([id]) => !listed.has(id)).map(([, hs]) => own(hs)),
    ];
  }, [checklist, set.holdings]);

  const shown = useMemo(() => {
    const q = settledQuery.trim().toLowerCase();
    const list = entries.filter(
      (e) => (show === "all" || (show === "owned") === owned(e)) && (!q || (!e.slot && e.card.name.toLowerCase().includes(q)) || (e.card.number ?? "").toLowerCase().includes(q)),
    );
    const nullLast = (n: number | null, dir: 1 | -1) => (n === null ? Infinity : dir * n);
    switch (sort) {
      case "number":
        return list;
      case "priceHigh":
        return [...list].sort((a, b) => nullLast(priceOf(a), -1) - nullLast(priceOf(b), -1));
      case "priceLow":
        return [...list].sort((a, b) => nullLast(priceOf(a), 1) - nullLast(priceOf(b), 1));
      case "name":
        return [...list].sort((a, b) => a.card.name.localeCompare(b.card.name));
      case "ownedFirst":
        return [...list.filter(owned), ...list.filter((e) => !owned(e))];
      case "missingFirst":
        return [...list.filter((e) => !owned(e)), ...list.filter(owned)];
    }
  }, [entries, settledQuery, show, sort]);

  if (store.status === "loading") return <SetSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  const name = checklist?.name ?? set.name;
  const total = entries.length;
  const ownedCount = entries.filter(owned).length;
  const known = Boolean(checklist);
  const ratio = total ? ownedCount / total : 0;
  const ownedValue = set.holdings.reduce((s, h) => s + (h.value ?? 0), 0);
  const toFinish = entries.filter((e) => !owned(e)).reduce((s, e) => s + (e.card.market ?? 0), 0);

  return (
    <div className="animate-fade-in">
      <Link href={MASTER_SETS} className="relative z-10 -ml-1 mb-4 inline-flex items-center gap-0.5 text-[13px] font-medium text-muted hover:text-foreground">
        <ChevronLeft className="size-4" /> Master sets
      </Link>
      <PageHeader
        title={name}
        className="mb-5"
        figure={
          loading ? (
            "—"
          ) : (
            <AnimatedNumber key={known ? "pct" : "count"} value={known ? ratio * 100 : ownedCount} format={(n) => (known ? `${Math.round(n)}%` : String(Math.round(n)))} duration={1100} />
          )
        }
        note={
          loading ? (
            "Loading the card list…"
          ) : known ? (
            <span className="flex items-center gap-2">
              <LimeChip>
                {ownedCount} of {total}
              </LimeChip>
              cards collected
            </span>
          ) : (
            `cards owned · ${error ?? "full list not in Holo yet"}`
          )
        }
        stats={
          known
            ? [
                { label: "You own", value: money(ownedValue) },
                { label: "To finish", value: toFinish > 0 && !sample ? money(toFinish) : "—" },
                { label: "Missing", value: total - ownedCount },
              ]
            : undefined
        }
      />
      {known && <SetStrip owned={entries.map(owned)} />}

      <div className="mt-6 space-y-3">
        <SearchSort query={query} onQuery={setQuery} placeholder="Search this set" sort={sort} onSort={setSort} sorts={SORTS} />
        <Segmented
          ariaLabel="Show"
          value={show}
          onChange={setShow}
          options={[
            { value: "all", label: <Count label="All" n={total} /> },
            { value: "owned", label: <Count label="Owned" n={ownedCount} /> },
            { value: "missing", label: <Count label="Missing" n={total - ownedCount} /> },
          ]}
        />
        {sort !== "number" && <p className="text-[13px] text-muted">Sorted by {SORTS.find((s) => s.value === sort)?.label.toLowerCase()}</p>}
      </div>

      {loading ? (
        <div className="mt-6 grid grid-cols-3 gap-x-2.5 gap-y-4 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-8 2xl:grid-cols-10">
          {Array.from({ length: 12 }).map((_, i) => (
            <Skeleton key={i} className="aspect-[63/88] rounded-lg" />
          ))}
        </div>
      ) : !shown.length ? (
        <p className="py-14 text-center text-[15px] text-muted">{show === "owned" ? "None owned yet." : show === "missing" ? "Nothing missing. Set complete." : "Nothing matches."}</p>
      ) : (
        <div className="mt-6 grid grid-cols-3 gap-x-2.5 gap-y-[18px] sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-8 2xl:grid-cols-10">
          {shown.map((e) => (
            <CardCell key={e.card.productId} entry={e} />
          ))}
        </div>
      )}
    </div>
  );
}

function Count({ label, n }: { label: string; n: number }) {
  return (
    <>
      {label} <span className="tabular opacity-60">{n}</span>
    </>
  );
}

/** One card of the set: in full color with a lime check if you own it, dimmed if not. */
function CardCell({ entry: e }: { entry: Entry }) {
  const hero = useHeroLink();
  const h = e.holdings[0];
  const qty = e.holdings.reduce((s, x) => s + x.quantity, 0);
  const price = priceOf(e);
  const href = `/product/${encodeURIComponent(e.card.productId)}`;

  const art = (
    <div className="relative aspect-[63/88] w-full">
      {h ? (
        <HoloTilt max={8} foil={h.product ? isFoilCard(h.product) : false} radius="4.5% / 3.2%" className="h-full w-full">
          <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} size="sm" frame={false} className="h-full w-full" />
        </HoloTilt>
      ) : e.card.imageUrl ? (
        // eslint-disable-next-line @next/next/no-img-element -- a missing card, ghosted
        <img src={e.card.imageUrl} alt="" loading="lazy" className="h-full w-full rounded-[4.5%/3.2%] object-cover opacity-[0.28] grayscale transition-opacity group-hover:opacity-50" />
      ) : (
        <div className="flex h-full w-full items-center justify-center rounded-md border border-dashed border-border-strong">
          <span className="font-mono text-[11px] text-subtle">#{e.card.number ?? "—"}</span>
        </div>
      )}
      {h && (
        <span className={cn("tabular absolute right-1.5 top-1.5 z-[3] flex h-5 min-w-5 items-center justify-center gap-0.5 rounded-full bg-lime text-[10px] font-bold text-[#0b0b0c]", qty > 1 && "px-1.5")}>
          <Check className="size-2.5" strokeWidth={4} />
          {qty > 1 && `×${qty}`}
        </span>
      )}
    </div>
  );

  const caption = (
    <>
      {!e.slot && <p className={cn("mt-1.5 truncate text-[12px] font-medium", !h && "text-muted")}>{e.card.name}</p>}
      {(!e.slot || h) && (
        <div className="mt-0.5 flex items-center gap-1">
          <span className="truncate font-mono text-[10px] text-subtle">#{e.card.number ?? "—"}</span>
          {price !== null && <span className={cn("tabular ml-auto shrink-0 text-[11px] font-semibold", !h && "text-muted")}>{money(price)}</span>}
        </div>
      )}
    </>
  );

  if (e.slot)
    return (
      <div className="min-w-0">
        {art}
        {caption}
      </div>
    );
  return (
    <Link href={href} onClick={(ev) => hero(ev, href)} className="group block min-w-0" title={e.card.name}>
      {art}
      {caption}
    </Link>
  );
}

/** The whole set as a strip of ticks, one per card, lime where you own it. */
function SetStrip({ owned }: { owned: boolean[] }) {
  const perRow = owned.length > 120 ? 40 : owned.length > 60 ? 30 : 20;
  const have = owned.filter(Boolean).length;
  return (
    <div
      role="img"
      aria-label={`${have} of ${owned.length} cards owned`}
      className="grid max-w-[720px] gap-x-[2px] gap-y-[3px]"
      style={{ gridTemplateColumns: `repeat(${perRow}, minmax(0, 1fr))` }}
    >
      {owned.map((on, i) => (
        <span key={i} className={cn("h-3 rounded-[1.5px]", on ? "bg-lime" : "bg-surface-3")} />
      ))}
    </div>
  );
}

function SetSkeleton() {
  return (
    <div aria-busy="true">
      <Skeleton className="h-4 w-24" />
      <Skeleton className="mt-6 h-4 w-40" />
      <Skeleton className="mt-3 h-14 w-48" />
      <Skeleton className="mt-6 h-16 w-full max-w-[720px]" />
      <div className="mt-8 grid grid-cols-3 gap-2.5 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6">
        {Array.from({ length: 12 }).map((_, i) => (
          <Skeleton key={i} className="aspect-[63/88] rounded-lg" />
        ))}
      </div>
    </div>
  );
}
