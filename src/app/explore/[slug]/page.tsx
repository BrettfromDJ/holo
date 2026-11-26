"use client";
/* eslint-disable @next/next/no-img-element -- set logos come from the pricing source's CDN */

import { FlipGrid, FlipItem } from "@/components/motion/flip-grid";
import { ArrowUpDown, Bell, BellRing, Check, ChevronLeft, Flame } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { ExploreBackdrop } from "@/components/explore/landing";
import { ProductTile, SetLogo, useOwnedIds } from "@/components/explore/explore-items";
import { ProductImage } from "@/components/product/product-image";
import { DropdownMenu, DropdownMenuContent, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { compareCollectorNumbers } from "@/lib/collector-number";
import { withEditionArt } from "@/lib/editions";
import { packCount, pricePerPack } from "@/lib/packs";
import type { ExploreProduct, ExploreSet } from "@/lib/explore/types";
import { formatDate, money } from "@/lib/format";
import { shortGameName } from "@/lib/games";
import { daysUntil, useReleaseReminders } from "@/lib/reminders";
import { rememberViewed } from "@/lib/search-history";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

type Tab = "single" | "sealed";
type Sort = "price" | "perPack" | "number" | "name";
const SORT_LABEL: Record<Sort, string> = { price: "Price: high to low", perPack: "Price per pack: low to high", number: "Collector number", name: "Name" };

/** Named or typed like sealed product (the catalog sometimes files a box as a single). Same as the app's `looksSealed`. */
const SEALED_WORDS = /\b(booster|box|bundle|pack|tin|collection|display|case|blister|deck|kit|trainer box|etb|starter)\b/i;

function productHref(item: ExploreProduct) {
  return `/product/${encodeURIComponent(item.product.id)}${item.printing ? `?printing=${encodeURIComponent(item.printing)}` : ""}`;
}

/**
 * A set's page (the app's SetView): its art and name (a countdown and bell before release), its
 * chase cards, then every product under Singles / Sealed chips with a sort, pinned as you scroll.
 */
export default function ExploreSetPage() {
  const { slug } = useParams<{ slug: string }>();
  const { today } = useStore();
  const [state, setState] = useState<{ set: ExploreSet; products: ExploreProduct[] } | { error: string } | null>(null);
  const [tab, setTab] = useState<Tab>("single");
  const [sortChoice, setSort] = useState<Sort>("price");
  const owned = useOwnedIds();

  useEffect(() => {
    fetch(`/api/explore/sets/${encodeURIComponent(slug)}`)
      .then(async (res) => {
        const body = await res.json().catch(() => null);
        if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't load this set.");
        return body as { set: ExploreSet; products: ExploreProduct[] };
      })
      .then(
        (b) => {
          setState(b);
          // Open on whichever tab has products.
          if (!b.products.some((p) => p.product.kind === "single") && b.products.some((p) => p.product.kind === "sealed")) setTab("sealed");
        },
        (e: Error) => setState({ error: e.message }),
      );
  }, [slug]);

  const set = state && "set" in state ? state.set : null;
  const products = useMemo(() => (state && "products" in state ? state.products : []), [state]);
  const gameSlug = set?.gameSlug ?? null;
  const { singles, sealed, chase } = useMemo(() => {
    const singles = products.filter((p) => p.product.kind === "single");
    const sealed = products.filter((p) => p.product.kind === "sealed");
    const chase = singles
      .filter((p) => p.market !== null && !SEALED_WORDS.test(`${p.product.name} ${p.product.productType ?? ""}`))
      .sort((a, b) => (b.market ?? 0) - (a.market ?? 0))
      .slice(0, 10);
    return { singles, sealed, chase };
  }, [products]);
  // Price per pack only applies to sealed products.
  const sort: Sort = tab === "single" && sortChoice === "perPack" ? "price" : sortChoice;
  const list = useMemo(() => {
    const l = (tab === "single" ? singles : sealed).slice();
    if (sort === "price") return l.sort((a, b) => (b.market ?? -1) - (a.market ?? -1));
    if (sort === "perPack") {
      const per = (p: ExploreProduct) => pricePerPack(p.market, packCount(p.product, gameSlug)) ?? Infinity;
      return l.sort((a, b) => per(a) - per(b));
    }
    if (sort === "number") return l.sort((a, b) => compareCollectorNumbers(a.product.number, b.product.number));
    return l.sort((a, b) => a.product.name.localeCompare(b.product.name));
  }, [singles, sealed, tab, sort, gameSlug]);

  const ownArt = Boolean(set?.logoUrl && set?.iconUrl);
  const upcoming = Boolean(set?.releaseDate && set.releaseDate >= today);

  return (
    <div className="relative isolate animate-fade-in">
      {!ownArt && <ExploreBackdrop />}
      {set ? (
        <Link href={`/explore/g/${encodeURIComponent(set.gameSlug)}`} className="mb-5 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
          <ChevronLeft className="size-4" /> {shortGameName(set.gameName)}
        </Link>
      ) : (
        <Link href="/explore" className="mb-5 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
          <ChevronLeft className="size-4" /> Explore
        </Link>
      )}

      {!state ? (
        <>
          <Skeleton className="h-24 w-full rounded-3xl" />
          <div className="mt-8 grid grid-cols-2 gap-x-3.5 gap-y-7 sm:grid-cols-3 lg:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="aspect-[5/7] rounded-2xl" />
            ))}
          </div>
        </>
      ) : "error" in state ? (
        <p className="py-20 text-center text-[14px] text-muted">{state.error}</p>
      ) : (
        <>
          {/* Our own set art: the background across the top of the page, blurred, with the logo on
              it. Other sets keep the framed banner above the title. */}
          {ownArt ? (
            <>
              <div
                aria-hidden
                className="pointer-events-none absolute -inset-x-4 -top-6 -z-10 h-[460px] overflow-hidden sm:-inset-x-8"
                style={{ maskImage: "linear-gradient(to bottom, black, black 42%, transparent 92%)", WebkitMaskImage: "linear-gradient(to bottom, black, black 42%, transparent 92%)" }}
              >
                <img src={state.set.iconUrl!} alt="" className="h-full w-full scale-110 object-cover blur-[16px] brightness-75" />
              </div>
              <div className="mb-5 flex h-[190px] items-center justify-center sm:h-[210px]">
                <img src={state.set.logoUrl!} alt={state.set.name} className="max-h-[150px] max-w-[min(300px,80%)] object-contain drop-shadow-[0_6px_14px_rgba(0,0,0,0.6)]" />
              </div>
            </>
          ) : state.set.iconUrl ? (
            <div className="relative mb-5 aspect-[3/2] w-full overflow-hidden rounded-[22px] shadow-[0_0_22px_color-mix(in_srgb,var(--lime)_22%,transparent)] sm:max-w-md">
              <img src={state.set.iconUrl} alt="" className="h-full w-full object-cover" />
              <SetLogo url={state.set.logoUrl} />
            </div>
          ) : state.set.imageUrl ? (
            <div className="mb-5 flex h-[180px] w-full items-center justify-center rounded-[22px] border border-border bg-image-well p-7 sm:max-w-md">
              <img src={state.set.imageUrl} alt="" className="max-h-full max-w-full object-contain" />
            </div>
          ) : null}

          <header className="space-y-2">
            <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{shortGameName(state.set.gameName)}</p>
            <h1 className="font-display text-[30px] leading-[1.02] tracking-[-0.035em] text-balance sm:text-[34px]">{state.set.name}</h1>
            <p className={cn("tabular text-[13px]", ownArt ? "text-white/80" : "text-muted")}>
              {[
                state.set.releaseDate && `${upcoming ? "Out" : "Released"} ${formatDate(state.set.releaseDate)}`,
                products.length ? `${products.length} product${products.length === 1 ? "" : "s"}` : null,
              ]
                .filter(Boolean)
                .join(" · ")}
            </p>
          </header>
          {upcoming && (
            <div className="mt-5">
              <ReleaseCountdown set={state.set} />
            </div>
          )}

          {products.length === 0 ? (
            <div className="mt-8 rounded-[20px] border border-border bg-surface p-[18px]">
              <p className="text-[16px] font-semibold">Cards for this set are on the way</p>
              <p className="mt-1 text-[14px] text-muted">
                {upcoming ? "Its cards and sealed products show up here once the set is out." : "The catalog adds a few sets each day. Check back soon."}
              </p>
            </div>
          ) : (
            <>
              {chase.length > 0 && <ChaseCards chase={chase} owned={owned} />}

              <div className="sticky top-[calc(3.5rem+env(safe-area-inset-top))] z-20 -mx-4 mt-9 flex items-center justify-between gap-3 bg-background/85 px-4 py-2 backdrop-blur-xl sm:-mx-8 sm:px-8 lg:top-0">
                <div role="radiogroup" aria-label="Product type" className="flex gap-2">
                  {(
                    [
                      ["single", "Singles", singles.length],
                      ["sealed", "Sealed", sealed.length],
                    ] as const
                  ).map(([value, label, count]) => {
                    const on = tab === value;
                    return (
                      <button
                        key={value}
                        type="button"
                        role="radio"
                        aria-checked={on}
                        onClick={() => setTab(value)}
                        className={cn(
                          "inline-flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-[13px] border px-3.5 text-[14px] font-medium transition-colors",
                          on ? "border-white bg-white text-[#0b0b0c]" : "border-white/10 bg-white/[0.06] text-white backdrop-blur-xl hover:bg-white/[0.1]",
                        )}
                      >
                        {label}
                        <span className={cn("tabular text-[13px]", on ? "text-[#0b0b0c]/55" : "text-white/60")}>{count}</span>
                      </button>
                    );
                  })}
                </div>
                <DropdownMenu>
                  <DropdownMenuTrigger aria-label="Sort" className="glass flex size-11 shrink-0 items-center justify-center rounded-full text-white outline-none">
                    <ArrowUpDown className="size-4" strokeWidth={2.4} />
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end" className="min-w-[220px]">
                    <DropdownMenuLabel>Sort by</DropdownMenuLabel>
                    <DropdownMenuRadioGroup value={sort} onValueChange={(v) => setSort(v as Sort)}>
                      {(Object.keys(SORT_LABEL) as Sort[])
                        .filter((s) => tab === "sealed" || s !== "perPack")
                        .map((s) => (
                          <DropdownMenuRadioItem key={s} value={s}>
                            {SORT_LABEL[s]}
                          </DropdownMenuRadioItem>
                        ))}
                    </DropdownMenuRadioGroup>
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>

              <p className="tabular mt-3 font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">
                {list.length} {tab === "single" ? "singles" : "sealed"} · {SORT_LABEL[sort]}
              </p>
              {list.length ? (
                <FlipGrid className="mt-3.5 grid grid-cols-2 gap-x-3.5 gap-y-7 sm:grid-cols-3 sm:gap-x-5 lg:grid-cols-4">
                  {list.map((item, i) => (
                    <FlipItem key={item.product.id} flipKey={item.product.id} index={i}>
                      <ProductTile item={item} owned={owned.has(item.product.id)} gameSlug={gameSlug} />
                    </FlipItem>
                  ))}
                </FlipGrid>
              ) : (
                <p className="py-[50px] text-center text-[14px] text-muted">No {tab === "single" ? "singles" : "sealed products"} in this set.</p>
              )}
            </>
          )}
        </>
      )}
    </div>
  );
}

/** Days to release in big lime numbers, with the reminder bell (the app's ReleaseCountdown). */
function ReleaseCountdown({ set }: { set: ExploreSet }) {
  const { today } = useStore();
  const reminders = useReleaseReminders();
  const on = reminders.has(set.slug);
  const days = Math.max(0, set.releaseDate ? daysUntil(set.releaseDate, today) : 0);
  return (
    <div className="glass flex items-center gap-3.5 rounded-[20px] p-4 sm:max-w-md">
      <div className="min-w-0 flex-1">
        <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{days === 0 ? "Out" : "Out in"}</p>
        <p className="mt-1.5 flex items-baseline gap-1.5">
          <span className="tabular font-display text-[44px] leading-none tracking-[-0.035em] text-[var(--lime)]">{days}</span>
          <span className="text-[14px] text-muted">{days === 0 ? "today" : days === 1 ? "day" : "days"}</span>
        </p>
      </div>
      <button
        type="button"
        onClick={() => {
          const now = reminders.toggle(set.slug);
          toast(now ? `We'll remind you about ${set.name}` : `Reminder removed for ${set.name}`);
        }}
        aria-pressed={on}
        className={cn("btn-3d inline-flex h-10 shrink-0 items-center gap-1.5 rounded-full px-4 text-[14px] font-semibold", on ? "btn-3d-lime bg-[var(--lime)] text-[#0b0b0c]" : "btn-3d-dark bg-surface-2 text-foreground")}
      >
        {on ? <BellRing className="size-4" /> : <Bell className="size-4" />} {on ? "Reminder on" : "Remind me"}
      </button>
    </div>
  );
}

/** The set's most valuable singles: the top one big, then a sideways row of the next nine with their rank. */
function ChaseCards({ chase, owned }: { chase: ExploreProduct[]; owned: Set<string> }) {
  const [first, ...rest] = chase;
  const p = withEditionArt(first.product, first.printing);
  return (
    <section aria-label="Chase cards" className="mt-9">
      <h2 className="mb-3.5 font-display text-[22px] leading-none tracking-[-0.03em]">Chase cards</h2>
      <Link
        href={productHref(first)}
        onClick={() => rememberViewed(first)}
        className="neon-frame relative flex items-center gap-[18px] overflow-hidden rounded-[22px] p-[18px] shadow-[0_0_18px_color-mix(in_srgb,var(--lime)_18%,transparent)] sm:max-w-xl"
      >
        <div aria-hidden className="absolute inset-0 -z-10" style={{ backgroundImage: "radial-gradient(200px 200px at 15% 50%, color-mix(in srgb, var(--lime) 20%, transparent), transparent)" }} />
        <ProductImage product={p} size="lg" frame={false} className="h-[168px] w-[120px] shrink-0" />
        <div className="min-w-0 flex-1 space-y-2.5">
          <div className="flex flex-wrap gap-1.5">
            <span className="tag-skew tag-lime">
              <Flame className="size-3" /> No. 1 chase
            </span>
            {owned.has(first.product.id) && <span className="tag-skew tag-blue">Owned</span>}
          </div>
          <p className="line-clamp-3 text-[17px] font-semibold leading-snug text-white">{first.product.name}</p>
          {first.product.rarity && first.product.rarity.toLowerCase() !== "none" && <p className="truncate text-[12px] text-muted">{first.product.rarity}</p>}
          <p className="tabular truncate font-display text-[34px] leading-none tracking-[-0.035em] text-white">{money(first.market)}</p>
        </div>
      </Link>
      {rest.length > 0 && (
        <div className="fade-row -mx-4 mt-3.5 overflow-x-auto px-4 py-1 [scrollbar-width:none] sm:-mx-8 sm:px-8 [&::-webkit-scrollbar]:hidden">
          <div className="flex gap-3">
            {rest.map((item, i) => (
              <Link key={item.product.id} href={productHref(item)} onClick={() => rememberViewed(item)} className="group w-[118px] shrink-0">
                <div className="relative">
                  <ProductImage product={withEditionArt(item.product, item.printing)} size="md" frame={false} className="h-[165px] w-[118px]" />
                  <span className="tag-skew tag-lime absolute left-1.5 top-1.5 font-display !text-[15px] !not-italic tracking-[-0.02em]">#{i + 2}</span>
                  {owned.has(item.product.id) && (
                    <span className="absolute bottom-1.5 right-1.5 flex size-5 items-center justify-center rounded-full bg-background/85 text-[var(--lime)]">
                      <Check className="size-3" />
                    </span>
                  )}
                </div>
                <p className="mt-2 truncate text-[13px] font-medium text-white">{item.product.name}</p>
                <p className="tabular mt-1 font-display text-[17px] leading-none tracking-[-0.03em] text-white">{money(item.market)}</p>
              </Link>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
