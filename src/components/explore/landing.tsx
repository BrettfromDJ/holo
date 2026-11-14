"use client";
/* eslint-disable @next/next/no-img-element -- set art and brand logos come from our files and the catalog's CDN */

import { ArrowRight, Bell, BellRing, Sparkles } from "lucide-react";
import Link from "next/link";
import { gridPattern } from "@/components/master-sets/master-set-items";
import type { ExploreGame, ExploreSet } from "@/lib/explore/types";
import { formatDate } from "@/lib/format";
import { daysUntil, useReleaseReminders } from "@/lib/reminders";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { logoTone, SetArt } from "./explore-items";

/**
 * Explore's landing, the app's layout (ExploreView): the lit grid behind the top, the catalog's
 * size, the next release as a big card with its countdown and reminder, sets coming soon and
 * just released as rows of art, then the brands as tinted cards.
 */

/** The lit grid behind the top of Explore (the app's ExploreBackdrop). */
export function ExploreBackdrop() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-x-0 -top-24 -z-10 h-[620px] [mask-image:linear-gradient(to_bottom,black,black_70%,transparent)]">
      <div className="absolute inset-0" style={{ ...gridPattern(36, "rgb(255 255 255 / 0.05)") }} />
      <div className="absolute inset-0" style={{ backgroundImage: "radial-gradient(260px 260px at 20% 30%, color-mix(in srgb, var(--lime) 22%, transparent), transparent), radial-gradient(240px 240px at 90% 55%, color-mix(in srgb, var(--plan-blue) 22%, transparent), transparent), radial-gradient(200px 200px at 60% 5%, color-mix(in srgb, var(--plan-pink) 16%, transparent), transparent)" }} />
    </div>
  );
}

function StatTile({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex-1 rounded-2xl border border-border bg-white/[0.05] px-4 py-3 backdrop-blur-xl">
      <p className="font-mono text-[11px] uppercase tracking-[0.1em] text-muted">{label}</p>
      <p className="tabular mt-1 font-display text-[24px] leading-none">{value.toLocaleString()}</p>
    </div>
  );
}

/** The catalog's size, then the next release (the app's CatalogHero). */
export function CatalogHero({ index, next }: { index: { games: ExploreGame[]; sets: ExploreSet[] }; next?: ExploreSet }) {
  const cards = index.games.reduce((n, g) => n + (g.cardCount ?? 0), 0);
  return (
    <div className="space-y-5">
      <div className="flex gap-2 sm:max-w-xl">
        <StatTile label="Brands" value={index.games.length} />
        <StatTile label="Sets" value={index.sets.length} />
        <StatTile label="Cards" value={cards} />
      </div>
      {next && <NextRelease set={next} />}
    </div>
  );
}

/** The next set to come out: its name and date, a big lime day count and a reminder (the app's NextRelease). */
function NextRelease({ set }: { set: ExploreSet }) {
  const { today } = useStore();
  const reminders = useReleaseReminders();
  const on = reminders.has(set.slug);
  const days = Math.max(0, set.releaseDate ? daysUntil(set.releaseDate, today) : 0);
  const art = set.iconUrl ?? set.imageUrl;
  return (
    <Link href={`/explore/${encodeURIComponent(set.slug)}`} className="neon-frame relative block overflow-hidden rounded-[22px] bg-[#070707] shadow-[0_0_36px_color-mix(in_srgb,var(--lime)_20%,transparent)] sm:max-w-xl">
      {art && <img src={art} alt="" className="absolute inset-0 h-full w-full object-cover opacity-[0.22] [mask-image:linear-gradient(to_right,transparent,black)]" />}
      <div aria-hidden className="absolute inset-0" style={{ backgroundImage: "radial-gradient(220px 220px at 100% 50%, color-mix(in srgb, var(--lime) 16%, transparent), transparent)" }} />
      <div className="relative flex items-center gap-4 py-[18px] pl-[18px] pr-5">
        <div className="min-w-0 flex-1 space-y-2.5">
          <span className="tag-skew tag-lime inline-flex items-center gap-1">
            <Sparkles className="size-3" /> Next release
          </span>
          <p className="font-display text-[24px] leading-[1.05] tracking-[-0.03em] text-balance">{set.name}</p>
          <p className="truncate text-[13px] text-muted">{[set.gameName, set.releaseDate ? formatDate(set.releaseDate) : null].filter(Boolean).join(" · ")}</p>
          <button
            type="button"
            onClick={(e) => {
              e.preventDefault();
              reminders.toggle(set.slug);
            }}
            className={cn("inline-flex h-9 items-center gap-1.5 rounded-full px-3.5 text-[13px] font-semibold", on ? "bg-[var(--lime)] text-[#0b0b0c]" : "bg-white/10 text-foreground hover:bg-white/15")}
          >
            {on ? <BellRing className="size-3.5" /> : <Bell className="size-3.5" />} {on ? "Reminder on" : "Remind me"}
          </button>
        </div>
        <div className="flex min-w-[70px] flex-col items-center gap-1.5">
          <span className="tabular rounded-lg bg-white/[0.07] px-2.5 py-1 font-display text-[56px] leading-none text-[var(--lime)]">{days}</span>
          <span className="font-mono text-[11px] uppercase tracking-[0.1em] text-muted">{days === 0 ? "today" : days === 1 ? "day" : "days"}</span>
        </div>
      </div>
    </Link>
  );
}

/** A heading with its subtitle, and an optional link on the right. */
export function LandingHeading({ title, subtitle, href, linkLabel }: { title: string; subtitle: string; href?: string; linkLabel?: string }) {
  return (
    <div className="mb-3.5 flex items-end justify-between gap-3">
      <div>
        <h2 className="font-display text-[22px] leading-none tracking-[-0.03em]">{title}</h2>
        <p className="mt-1.5 text-[14px] text-muted">{subtitle}</p>
      </div>
      {href && (
        <Link href={href} className="flex shrink-0 items-center gap-1 text-[13px] font-medium text-muted hover:text-foreground">
          {linkLabel} <ArrowRight className="size-3.5" />
        </Link>
      )}
    </div>
  );
}

/** A sideways row of sets as art tiles (the app's SetCarousel). */
export function SetCarousel({ sets, upcoming }: { sets: ExploreSet[]; upcoming: boolean }) {
  return (
    <div className="-mx-4 overflow-x-auto px-4 pb-1 [scrollbar-width:none] sm:-mx-8 sm:px-8 [&::-webkit-scrollbar]:hidden">
      <div className="flex gap-3">
        {sets.map((s) => (
          <SetCard key={s.slug} set={s} upcoming={upcoming} />
        ))}
      </div>
    </div>
  );
}

/** A set: its art (with "In N days" and a bell for coming ones), name, brand and date (the app's SetTile). */
function SetCard({ set, upcoming }: { set: ExploreSet; upcoming: boolean }) {
  const { today } = useStore();
  const reminders = useReleaseReminders();
  const days = set.releaseDate ? daysUntil(set.releaseDate, today) : null;
  return (
    <Link href={`/explore/${encodeURIComponent(set.slug)}`} className="group w-[170px] shrink-0 sm:w-[200px]">
      <div className="relative aspect-[3/2] overflow-hidden rounded-2xl border border-border">
        <SetArt set={set} className="h-full w-full" />
        {upcoming && days !== null && (
          <span className={cn("tag-skew absolute left-2.5 top-2.5", days <= 7 ? "tag-lime" : "tag-blue")}>{days <= 0 ? "Out today" : `In ${days} day${days === 1 ? "" : "s"}`}</span>
        )}
        {upcoming && reminders.has(set.slug) && (
          <span className="absolute right-2 top-2 flex size-6 items-center justify-center rounded-full bg-[var(--lime)] text-[#0b0b0c]">
            <BellRing className="size-3" />
          </span>
        )}
      </div>
      <p className="mt-2.5 truncate text-[14px] font-medium">{set.name}</p>
      <p className="tabular truncate text-[12px] text-muted">{[set.gameName, set.releaseDate ? formatDate(set.releaseDate) : null].filter(Boolean).join(" · ")}</p>
    </Link>
  );
}

const TINTS = ["tint-lime", "tint-pink", "tint-blue", "tint-azure"];

/** A brand as a tinted card: its logo, name, and how many sets and cards (the app's BrandCard). */
export function BrandCard({ game, i }: { game: ExploreGame; i: number }) {
  return (
    <Link href={`/explore/g/${encodeURIComponent(game.slug)}`} className={cn("tint group flex min-h-[124px] flex-col items-center justify-center gap-3 rounded-[var(--radius-card)] p-3.5 text-center transition-transform duration-300 hover:-translate-y-1", TINTS[i % TINTS.length])}>
      <div className="flex h-11 w-full items-center justify-center">
        {game.logoUrl ? (
          <img src={game.logoUrl} alt="" loading="lazy" className={cn("max-h-full max-w-[80%] object-contain drop-shadow-[0_8px_18px_rgba(0,0,0,0.5)]", logoTone(game))} />
        ) : (
          <span className="font-display text-[26px] leading-none text-[var(--tint)]">{game.name.slice(0, 1).toUpperCase()}</span>
        )}
      </div>
      <div className="min-w-0">
        <p className="truncate text-[15px] font-semibold">{game.name}</p>
        <p className="tabular truncate text-[12px] text-muted">
          {game.sets} sets{game.cardCount ? ` · ${game.cardCount.toLocaleString()} cards` : ""}
        </p>
      </div>
    </Link>
  );
}
