"use client";

import { ExternalLink, Loader2 } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useInView } from "@/components/motion/reveal";
import { Badge } from "@/components/ui/badge";
import { EBAY_SOURCE, sampleEbaySales } from "@/lib/ebay-sample";
import type { EbaySales as EbayData } from "@/lib/ebay-types";
import { formatShortDate, money, relativeTime } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { priceKey, type Grade } from "@/lib/types";
import { cn } from "@/lib/utils";

/** Results kept on this device for 12 hours, so revisiting a card doesn't spend credits. */
const TTL = 12 * 60 * 60 * 1000;
const memory = new Map<string, { at: number; value: EbayData | null }>();

type Load = { state: "idle" | "loading" } | { state: "ready"; data: EbayData | null } | { state: "error"; message: string; tier: boolean };

function readCache(key: string) {
  const hit = memory.get(key);
  if (hit && Date.now() - hit.at < TTL) return hit;
  try {
    const raw = localStorage.getItem(`holo:ebay:${key}`);
    const v = raw ? (JSON.parse(raw) as { at: number; value: EbayData | null }) : null;
    if (v && Date.now() - v.at < TTL) {
      memory.set(key, v);
      return v;
    }
  } catch {
    /* storage unavailable */
  }
  return null;
}

function writeCache(key: string, value: EbayData | null) {
  const v = { at: Date.now(), value };
  memory.set(key, v);
  try {
    localStorage.setItem(`holo:ebay:${key}`, JSON.stringify(v));
  } catch {
    /* storage full or unavailable */
  }
}

/** Fetch a card's recent eBay sales once it's on screen. */
function useEbay(productId: string, printing: string | null, active: boolean) {
  const key = `${productId}:${printing ?? ""}`;
  // Starts idle on both server and client; the device cache is read after mount.
  const [load, setLoad] = useState<Load>({ state: "idle" });
  useEffect(() => {
    const hit = readCache(key);
    if (hit) return setLoad({ state: "ready", data: hit.value });
    if (!active) return;
    let cancelled = false;
    setLoad({ state: "loading" });
    fetch(`/api/tcg/products/${encodeURIComponent(productId)}/ebay${printing ? `?printing=${encodeURIComponent(printing)}` : ""}`)
      .then(async (r) => {
        const body = await r.json().catch(() => null);
        if (!r.ok) throw Object.assign(new Error(body?.error?.message ?? "Couldn't load eBay sales."), { tier: body?.error?.code === "tier" });
        return (body?.ebay ?? null) as EbayData | null;
      })
      .then((data) => {
        writeCache(key, data);
        if (!cancelled) setLoad({ state: "ready", data });
      })
      .catch((err: Error & { tier?: boolean }) => !cancelled && setLoad({ state: "error", message: err.message, tier: Boolean(err.tier) }));
    return () => {
      cancelled = true;
    };
  }, [key, productId, printing, active]);
  return load;
}

const UNGRADED = "Ungraded";

/**
 * Recent eBay sold listings: the 30-day median, how many sold and the last
 * sale, for ungraded copies or any grade that has sold, then the sales
 * themselves with links to the listings. Opens on `grade` when it has sold.
 */
export function EbaySales({
  productId,
  printing,
  grade,
  className,
  bare,
  name,
  market,
}: {
  productId: string;
  printing: string | null;
  grade?: Grade | null;
  className?: string;
  bare?: boolean;
  /** Name and ungraded market price, for sample sales when the product isn't in the store. */
  name?: string;
  market?: number | null;
}) {
  const [ref, inView] = useInView<HTMLDivElement>("0px 0px 200px 0px");
  const { data: store, today } = useStore();
  const sampleMode = EBAY_SOURCE === "sample";
  const sample = useMemo(() => {
    if (!sampleMode) return null;
    const raw = market !== undefined ? market : (store.prices[priceKey(productId, printing)]?.market ?? null);
    return sampleEbaySales(productId, name ?? store.products[productId]?.name ?? "Card", printing, raw, today);
  }, [sampleMode, market, name, productId, printing, store.prices, store.products, today]);
  // Until TCG API Pro is connected, sales are made up here and nothing is fetched.
  const fetched = useEbay(productId, printing, inView && !sampleMode);
  const load: Load = sampleMode ? { state: "ready", data: sample } : fetched;
  const data = load.state === "ready" ? load.data : null;
  const labels = useMemo(() => (data ? Object.entries(data.graded).sort((a, b) => b[1].count - a[1].count).map(([l]) => l) : []), [data]);
  const preferred = grade ? `${grade.company} ${grade.grade}` : null;
  const [picked, setPicked] = useState<string | null>(null);
  const tab = picked ?? (preferred && labels.includes(preferred) ? preferred : UNGRADED);
  const [all, setAll] = useState(false);

  const stats = data ? (tab === UNGRADED ? data.ungraded : data.graded[tab]) : null;
  const sales = data ? data.sales.filter((s) => (tab === UNGRADED ? s.grade === null : s.grade === tab)) : [];
  const shown = all ? sales : sales.slice(0, 6);

  return (
    <div ref={ref} className={cn(!bare && "rounded-[var(--radius-card)] border border-border bg-surface p-5 sm:p-6", className)}>
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <h2 className="flex items-center gap-2 text-[15px] font-semibold">
          Recent eBay sales
          {sampleMode && data && <Badge variant="sample">Sample data</Badge>}
        </h2>
        {data && (
          <p className="text-[12px] text-muted">
            Last 30 days · as of {formatShortDate(data.asOf)}
            {data.days !== null && data.days < 30 && ` · ${data.days} days tracked`}
          </p>
        )}
      </div>

      {(load.state === "idle" || load.state === "loading") && (
        <p className="flex items-center gap-2 py-6 text-[13px] text-muted">
          <Loader2 className="size-4 animate-spin" /> Loading sold listings…
        </p>
      )}
      {load.state === "error" && <p className="py-4 text-[13px] text-muted">{load.tier ? "eBay sold listings need TCG API's Pro plan. Upgrade in your TCG API dashboard to see them here." : load.message}</p>}
      {load.state === "ready" && !data && <p className="py-4 text-[13px] text-muted">No eBay sales tracked for this card yet.</p>}

      {data && (
        <>
          {labels.length > 0 && (
            <div className="scrollbar-none -mx-1 mt-3 flex gap-1.5 overflow-x-auto px-1 py-1">
              {[UNGRADED, ...labels].map((l) => (
                <button
                  key={l}
                  type="button"
                  onClick={() => {
                    setPicked(l);
                    setAll(false);
                  }}
                  className={cn("h-8 shrink-0 rounded-full px-3 text-[13px] transition-colors", tab === l ? "bg-foreground font-semibold text-background" : "bg-surface-2 text-muted hover:text-foreground")}
                >
                  {l}
                  <span className="tabular ml-1.5 opacity-60">{l === UNGRADED ? data.ungraded.count : data.graded[l].count}</span>
                </button>
              ))}
            </div>
          )}

          <dl className="mt-4 grid grid-cols-[minmax(0,1.2fr)_minmax(0,0.6fr)_minmax(0,1.2fr)] gap-3">
            <div>
              <dt className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">Median sold</dt>
              <dd className="tabular mt-1 text-[clamp(16px,4.8vw,24px)] font-semibold leading-none tracking-[-0.02em]">{stats?.median !== null && stats?.median !== undefined ? money(stats.median) : "—"}</dd>
            </div>
            <div>
              <dt className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">Sold</dt>
              <dd className="tabular mt-1 text-[clamp(16px,4.8vw,24px)] font-semibold leading-none tracking-[-0.02em]">{stats?.count ?? 0}</dd>
            </div>
            <div>
              <dt className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">Last sale</dt>
              <dd className="tabular mt-1 text-[clamp(16px,4.8vw,24px)] font-semibold leading-none tracking-[-0.02em]">{stats?.lastPrice !== null && stats?.lastPrice !== undefined ? money(stats.lastPrice) : "—"}</dd>
              {stats?.lastSold && <dd className="mt-1 text-[11px] text-muted">{relativeTime(stats.lastSold)}</dd>}
            </div>
          </dl>

          {sales.length ? (
            <ul className="mt-5 divide-y divide-border">
              {shown.map((s, i) => (
                <li key={`${s.url}-${i}`}>
                  <a href={s.url} target="_blank" rel="noreferrer" className="group flex items-center gap-3 py-2.5">
                    <span className="w-14 shrink-0 text-[12px] text-muted">{formatShortDate(s.soldDate)}</span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[13px] text-foreground/85 group-hover:text-foreground">{s.title}</span>
                      <span className="mt-0.5 flex flex-wrap gap-1.5 text-[11px] text-muted">
                        {s.condition && <span className="whitespace-nowrap rounded-full bg-surface-2 px-1.5">{s.condition}</span>}
                        {s.bestOffer && <span className="whitespace-nowrap rounded-full bg-surface-2 px-1.5">Best offer</span>}
                        {s.bestOffer && s.listPrice !== null && <span className="tabular whitespace-nowrap">listed {money(s.listPrice)}</span>}
                      </span>
                    </span>
                    <span className="tabular shrink-0 text-[15px] font-semibold">{money(s.price)}</span>
                    <ExternalLink className="size-3.5 shrink-0 text-subtle group-hover:text-foreground" />
                  </a>
                </li>
              ))}
            </ul>
          ) : (
            <p className="mt-4 text-[13px] text-muted">No {tab === UNGRADED ? "ungraded" : tab} sales in the last 30 days.</p>
          )}
          {sales.length > 6 && (
            <button type="button" onClick={() => setAll((v) => !v)} className="mt-2 text-[12px] font-medium text-muted hover:text-foreground">
              {all ? "Show fewer" : `Show all ${sales.length}`}
            </button>
          )}
        </>
      )}
    </div>
  );
}
