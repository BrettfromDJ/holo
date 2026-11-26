"use client";

import { useCallback, useEffect, useState } from "react";
import type { ExploreProduct } from "./explore/types";

/**
 * Recent searches and recently viewed products, kept in this browser (the app's SearchHistory:
 * up to 8 searches and 12 products). Views are recorded when a product link is clicked
 * (`rememberViewed`), so nothing runs on the product page itself.
 */

const QUERIES_KEY = "holo:search:recent-queries";
const VIEWED_KEY = "holo:search:recently-viewed";
const EVENT = "holo-search-history";

function read<T>(key: string): T[] {
  try {
    const raw = localStorage.getItem(key);
    const v = raw ? JSON.parse(raw) : [];
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

function write(key: string, value: unknown[]) {
  try {
    if (value.length) localStorage.setItem(key, JSON.stringify(value));
    else localStorage.removeItem(key);
  } catch {
    // Private mode or full storage: history is a convenience.
  }
  window.dispatchEvent(new Event(EVENT));
}

export function rememberQuery(query: string) {
  const q = query.trim();
  if (q.length < 2) return;
  write(QUERIES_KEY, [q, ...read<string>(QUERIES_KEY).filter((x) => x.toLowerCase() !== q.toLowerCase())].slice(0, 8));
}

export function forgetQuery(query: string) {
  write(QUERIES_KEY, read<string>(QUERIES_KEY).filter((x) => x !== query));
}

/** Records a product as viewed (call from a link's onClick). Only what a row needs is kept. */
export function rememberViewed(item: Pick<ExploreProduct, "product" | "printing" | "market"> & Partial<Pick<ExploreProduct, "priceUpdatedAt" | "gameName">>) {
  if (typeof window === "undefined") return;
  const p = item.product;
  const slim: ExploreProduct = {
    product: { ...p },
    printing: item.printing ?? null,
    market: item.market ?? null,
    priceUpdatedAt: item.priceUpdatedAt ?? null,
    gameName: item.gameName ?? null,
  };
  write(VIEWED_KEY, [slim, ...read<ExploreProduct>(VIEWED_KEY).filter((x) => x?.product?.id !== p.id)].slice(0, 12));
}

export function clearSearchHistory() {
  try {
    localStorage.removeItem(QUERIES_KEY);
    localStorage.removeItem(VIEWED_KEY);
  } catch {
    // ignore
  }
  window.dispatchEvent(new Event(EVENT));
}

/** The saved searches and views, kept current across tabs and components. */
export function useSearchHistory() {
  const [state, setState] = useState<{ queries: string[]; viewed: ExploreProduct[] }>({ queries: [], viewed: [] });
  const load = useCallback(() => setState({ queries: read<string>(QUERIES_KEY), viewed: read<ExploreProduct>(VIEWED_KEY).filter((x) => x?.product?.id) }), []);
  useEffect(() => {
    load();
    const onStorage = (e: StorageEvent) => {
      if (e.key === QUERIES_KEY || e.key === VIEWED_KEY) load();
    };
    window.addEventListener(EVENT, load);
    window.addEventListener("storage", onStorage);
    return () => {
      window.removeEventListener(EVENT, load);
      window.removeEventListener("storage", onStorage);
    };
  }, [load]);
  return state;
}
