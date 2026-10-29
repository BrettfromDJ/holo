"use client";

import { useEffect, useState } from "react";
import type { ExploreProduct } from "./types";

export type SearchLoad = { status: "loading" } | { status: "error"; message: string } | { status: "ready"; data: ExploreProduct[] };

/** Debounced catalog search, served from Supabase (never the TCG API). Null until the query has 2+ characters. */
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
          return body.products as ExploreProduct[];
        })
        .then(
          (data) => !cancelled && setResults({ status: "ready", data }),
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
