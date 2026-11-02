"use client";

import { useEffect, useState } from "react";
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
          return { data: body.products as ExploreProduct[], fuzzy: body.fuzzy === true };
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
