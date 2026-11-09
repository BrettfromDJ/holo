"use client";

import { Check, ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useDeferredValue, useMemo, useState } from "react";
import { DotMatrix, GlowPie, gridPattern, MASTER_SETS, SearchSort } from "@/components/master-sets/master-set-items";
import { HoloTilt, isFoilCard } from "@/components/motion/holo-tilt";
import { ErrorState } from "@/components/portfolio/error-state";
import { ProductImage } from "@/components/product/product-image";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { useChecklist, type OwnedSet } from "@/lib/checklists";
import { compareCollectorNumbers } from "@/lib/collector-number";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money, moneyWhole } from "@/lib/format";
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
  const ownedValue = set.holdings.reduce((s, h) => s + (h.value ?? 0), 0);
  const toFinish = entries.filter((e) => !owned(e)).reduce((s, e) => s + (e.card.market ?? 0), 0);

  return (
    <div className="animate-fade-in">
      <SetHero
        name={name}
        loading={loading}
        known={known}
        owned={entries.map(owned)}
        ownedValue={ownedValue}
        toFinish={toFinish > 0 && !sample ? toFinish : null}
        note={error ?? "full list not in Holo yet"}
      />

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
        <img src={e.card.imageUrl} alt="" loading="lazy" className="h-full w-full rounded-[4.5%/3.2%] object-cover opacity-[0.32] transition-opacity group-hover:opacity-50" />
      ) : (
        <div className="flex h-full w-full items-center justify-center rounded-md border border-dashed border-border-strong">
          <span className="font-mono text-[11px] text-subtle">#{e.card.number ?? "—"}</span>
        </div>
      )}
      {h && (
        <span className={cn("tabular absolute right-1.5 top-1.5 z-[3] flex h-5 min-w-5 items-center justify-center gap-0.5 rounded-full bg-lime text-[10px] font-bold text-[#0b0b0c]", qty > 1 && "px-1.5")}>
          <Check className="size-2.5" strokeWidth={2.5} />
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



/**
 * The set's top, like the app's: on a dark lit grid that runs up under the top of the page, the
 * name, the % in glowing lime dot-matrix digits, a dial of how much you own, two glass tiles
 * (what you own is worth, what finishing would cost), then every card in the set as one tick.
 */
function SetHero({
  name,
  loading,
  known,
  owned,
  ownedValue,
  toFinish,
  note,
}: {
  name: string;
  loading: boolean;
  known: boolean;
  owned: boolean[];
  ownedValue: number;
  toFinish: number | null;
  note: string;
}) {
  const total = owned.length;
  const have = owned.filter(Boolean).length;
  const ratio = total ? have / total : 0;
  const pct = Math.round(ratio * 100);
  return (
    <section className="relative isolate -mx-4 -mt-6 mb-6 [--hero-glow-x:50%] lg:[--hero-glow-x:62%] overflow-hidden rounded-b-[34px] bg-[#050505] px-4 pb-6 pt-4 text-white sm:-mx-8 sm:-mt-10 sm:px-8 sm:pb-8 sm:pt-7 lg:rounded-b-[40px]">
      <div aria-hidden className="absolute inset-0 -z-10" style={gridPattern(28)} />
      <div
        aria-hidden
        className="absolute inset-0 -z-10"
        style={{
          backgroundImage: [
            "radial-gradient(300px 300px at var(--hero-glow-x, 50%) 45%, color-mix(in srgb, var(--lime) 20%, transparent), transparent)",
            "radial-gradient(260px 260px at 95% 10%, color-mix(in srgb, var(--plan-blue) 18%, transparent), transparent)",
            "radial-gradient(240px 240px at 5% 85%, color-mix(in srgb, var(--plan-pink) 14%, transparent), transparent)",
          ].join(", "),
        }}
      />
      <Link href={MASTER_SETS} className="-ml-1 inline-flex items-center gap-0.5 text-[13px] font-medium text-white/55 hover:text-white">
        <ChevronLeft className="size-4" /> Master sets
      </Link>
      <h1 className="mt-3 text-balance font-display text-[24px] font-semibold leading-tight sm:text-[30px]">{name}</h1>

      <div className="mt-5 flex flex-col items-center gap-y-6 lg:mt-4 lg:grid lg:max-w-[940px] lg:grid-cols-[minmax(0,540px)_auto] lg:items-center lg:justify-between lg:gap-x-12">
        <div className="flex w-full flex-col items-center lg:items-start">
          {/* With the full list, the % sits inside the dial (below); otherwise the count shows here. */}
          {!(known && !loading) && (
            <>
              <p className="font-mono text-[11px] uppercase tracking-[0.15em] text-white/55">{loading ? "Complete" : "Cards owned"}</p>
              <div className="mt-2 flex h-[61px] items-start gap-1">
                {loading ? <DotMatrix text="--" dot={7} color="rgb(255 255 255 / 0.25)" glow={0} /> : <DotMatrix text={String(have)} dot={7} glow={16} />}
              </div>
              <p className="tabular mt-2 text-[13px] text-white/55">{loading ? "Loading the card list…" : note}</p>
            </>
          )}

          {known && !loading && (
            <div className="hidden w-full grid-cols-2 gap-2.5 lg:grid">
              <HeroTiles ownedValue={ownedValue} toFinish={toFinish} />
            </div>
          )}
        </div>

        {known && !loading && (
          <>
            {/* No drop-shadow filter here: a filter on the dial would stop its glass track blurring what's behind it. */}
            <GlowPie fraction={ratio} size={260} className="lg:mr-6">
              <p className="font-mono text-[10px] uppercase tracking-[0.14em] text-white/55">Complete</p>
              <div className="mt-1 flex items-start gap-0.5">
                <DotMatrix text={String(pct)} dot={5.2} glow={12} />
                <span className="-mt-0.5 text-[14px] text-lime">%</span>
              </div>
              <p className="tabular mt-1 text-[12px] text-white/55">
                {have} of {total}
              </p>
            </GlowPie>
            <div className="grid w-full grid-cols-2 gap-2.5 lg:hidden">
              <HeroTiles ownedValue={ownedValue} toFinish={toFinish} />
            </div>
          </>
        )}
      </div>

    </section>
  );
}

/** Two money figures only: the counts are in the dial and the chips below. */
function HeroTiles({ ownedValue, toFinish }: { ownedValue: number; toFinish: number | null }) {
  return (
    <>
      <HeroTile label="Yours worth" value={moneyWhole(ownedValue)} />
      <HeroTile
        label="To finish"
        value={toFinish !== null && toFinish > 0 ? moneyWhole(toFinish) : "Not priced"}
        dim={!(toFinish !== null && toFinish > 0)}
        note={toFinish !== null && toFinish > 0 ? `Full set ${moneyWhole(toFinish + ownedValue)}` : undefined}
      />
    </>
  );
}

/** A glass tile on the set's lit grid. */
function HeroTile({ label, value, dim, note }: { label: string; value: string; dim?: boolean; note?: string }) {
  return (
    <div className="min-h-[80px] min-w-0 rounded-[20px] border border-white/10 bg-white/[0.06] px-3.5 py-3 shadow-[inset_0_1px_0_rgb(255_255_255/0.08)] backdrop-blur-md">
      <p className="font-mono text-[10px] uppercase tracking-[0.12em] text-white/55">{label}</p>
      <p className={cn("tabular mt-1.5 truncate font-semibold tracking-[-0.03em]", dim ? "text-[17px] text-white/55" : "text-[24px]")}>{value}</p>
      {note && <p className="tabular mt-1 truncate text-[12px] text-white/55">{note}</p>}
    </div>
  );
}

function SetSkeleton() {
  return (
    <div aria-busy="true">
      <div className="-mx-4 -mt-6 h-[420px] rounded-b-[34px] bg-[#050505] sm:-mx-8 sm:-mt-10" />
      <div className="mt-8 grid grid-cols-3 gap-2.5 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6">
        {Array.from({ length: 12 }).map((_, i) => (
          <Skeleton key={i} className="aspect-[63/88] rounded-lg" />
        ))}
      </div>
    </div>
  );
}
