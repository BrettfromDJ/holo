"use client";

import { useEffect, useState } from "react";
import { isOversized } from "./movers";
import type { ExploreProduct } from "./types";

export type SearchLoad = { status: "loading" } | { status: "error"; message: string } | { status: "ready"; data: ExploreProduct[]; fuzzy?: boolean };

/**
 * Debounced catalog search, served from Supabase (never the TCG API). Null until the query has 2+ characters.
 * `fuzzy` is true when nothing matched exactly and these are close spellings.
 */
export function useCatalogSearch(query: string): SearchLoad | null {
  const [results, setResults] = useState<SearchLoad | null>(null);
  useEffect(() => {
    const q = query.trim();
    if (q.length < 2) return setResults(null);
    setResults({ status: "loading" });
    let cancelled = false;
    const t = window.setTimeout(() => {
      fetch(`/api/explore/search?q=${encodeURIComponent(q)}`)
        .then(async (res) => {
          const body = await res.json().catch(() => null);
          if (!res.ok) throw new Error(body?.error?.message ?? "Search failed.");
          // Oversized (jumbo) cards are never shown.
          return { data: (body.products as ExploreProduct[]).filter((p) => !isOversized(p.product)), fuzzy: body.fuzzy === true };
        })
        .then(
          ({ data, fuzzy }) => !cancelled && setResults({ status: "ready", data, fuzzy }),
          (e: Error) => !cancelled && setResults({ status: "error", message: e.message }),
        );
    }, 300);
    return () => {
      cancelled = true;
      window.clearTimeout(t);
    };
  }, [query]);
  return results;
}

export type PagedSearch =
  | { status: "loading"; query: string }
  | { status: "error"; query: string; message: string }
  | { status: "ready"; query: string; data: ExploreProduct[]; total: number; fetched: number; fuzzy: boolean; live?: boolean };

const PAGE = 40;

async function fetchPage(q: string, offset: number) {
  const res = await fetch(`/api/explore/search?q=${encodeURIComponent(q)}&offset=${offset}&limit=${PAGE}`);
  const body = await res.json().catch(() => null);
  if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't search right now. Check your connection.");
  const raw = (body?.products ?? []) as ExploreProduct[];
  return { raw: raw.length, data: raw.filter((p) => !isOversized(p.product)), total: Number(body?.total ?? raw.length), fuzzy: body?.fuzzy === true };
}

/**
 * The search page's catalog search (the app's SearchScreen): the stored catalog a page of 40 at a
 * time with the total, `loadMore` for the next page, pages kept per query so going back is
 * instant, and `searchLive` for one paid TCG API look, only ever on an explicit tap.
 */
export function usePagedCatalogSearch(query: string) {
  const [state, setState] = useState<PagedSearch | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [liveSearching, setLiveSearching] = useState(false);
  const [liveFor, setLiveFor] = useState("");
  const [cache] = useState(() => new Map<string, Extract<PagedSearch, { status: "ready" }>>());
  const q = query.trim();

  useEffect(() => {
    if (q.length < 2) return setState(null);
    const hit = cache.get(q.toLowerCase());
    if (hit) return setState(hit);
    // The old results stay up during the short pause in typing.
    setState((s) => (s?.status === "ready" ? s : { status: "loading", query: q }));
    let cancelled = false;
    const t = window.setTimeout(() => {
      setState((s) => (s?.status === "ready" && s.query === q ? s : { status: "loading", query: q }));
      fetchPage(q, 0).then(
        (p) => {
          if (cancelled) return;
          const ready = { status: "ready" as const, query: q, data: p.data, total: p.total, fetched: p.raw, fuzzy: p.fuzzy };
          cache.set(q.toLowerCase(), ready);
          setState(ready);
        },
        (e: Error) => !cancelled && setState({ status: "error", query: q, message: e.message }),
      );
    }, 220);
    return () => {
      cancelled = true;
      window.clearTimeout(t);
    };
  }, [q, cache]);

  const loadMore = async () => {
    if (!state || state.status !== "ready" || state.live || loadingMore || state.fetched >= state.total || state.query !== q) return;
    setLoadingMore(true);
    try {
      const p = await fetchPage(q, state.fetched);
      const seen = new Set(state.data.map((d) => `${d.product.id}|${d.printing}`));
      const next = {
        ...state,
        data: [...state.data, ...p.data.filter((d) => !seen.has(`${d.product.id}|${d.printing}`))],
        fetched: state.fetched + p.raw,
        // A short page means the end, whatever the total said.
        total: p.raw === 0 ? state.fetched : state.total,
      };
      cache.set(q.toLowerCase(), next);
      setState((s) => (s?.status === "ready" && s.query === q ? next : s));
    } catch {
      // Scrolling back down tries again.
    } finally {
      setLoadingMore(false);
    }
  };

  /** One paid look in TCG API's live catalog, for things the stored catalog doesn't have yet. */
  const searchLive = async () => {
    if (q.length < 2 || liveSearching || liveFor === q) return;
    setLiveSearching(true);
    try {
      const res = await fetch(`/api/tcg/search?q=${encodeURIComponent(q)}&type=all&game=all`);
      const body = await res.json().catch(() => null);
      if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't search the live catalog.");
      const hits = ((body?.hits ?? []) as ExploreProduct[]).filter((h) => !isOversized(h.product));
      const ready = { status: "ready" as const, query: q, data: hits, total: hits.length, fetched: hits.length, fuzzy: false, live: true };
      cache.set(q.toLowerCase(), ready);
      setLiveFor(q);
      setState(ready);
    } catch (e) {
      // Usually today's limit for live searches: say so rather than "nothing found".
      setState({ status: "error", query: q, message: (e as Error).message });
    } finally {
      setLiveSearching(false);
    }
  };

  return { state, loadMore, loadingMore, searchLive, liveSearching, liveTried: liveFor === q && q.length >= 2 };
}
