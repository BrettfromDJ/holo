"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { HoldingView } from "@/lib/finance/portfolio";
import { askingPrice, LIST_META_KEY, listShareTitle, parseListMeta, type ListMeta, type ListMetaMap } from "@/lib/lists";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useSyncedState } from "@/lib/store/synced-state";
import { getBrowserSupabase } from "@/lib/supabase/client";
import type { Product } from "@/lib/types";
import { listPrice } from "./list-row";

/** A list's extras (for sale, asking %, own prices), in user_state `list-meta`, shared with the app. */
export function useListMeta() {
  const [raw, setRaw, ready] = useSyncedState<ListMetaMap>(LIST_META_KEY, {});
  const all = useMemo(() => parseListMeta(raw), [raw]);
  const update = useCallback(
    (listId: string, fn: (m: ListMeta) => ListMeta) =>
      setRaw((prev) => {
        const parsed = parseListMeta(prev);
        return { ...parsed, [listId]: fn(parsed[listId] ?? {}) };
      }),
    [setRaw],
  );
  const drop = useCallback(
    (listId: string) =>
      setRaw((prev) => {
        const next = { ...parseListMeta(prev) };
        delete next[listId];
        return next;
      }),
    [setRaw],
  );
  return { all, ready, meta: (id: string): ListMeta => all[id] ?? {}, update, drop };
}

/** One card on a list, worked out like the app's `ListItemInfo`. */
export interface ListItemInfo {
  productId: string;
  product: Product | undefined;
  /** Your copies (most valuable first); empty when you don't own it. */
  copies: HoldingView[];
  market: number | null;
  /** How many to count in totals: what you own, or one. */
  count: number;
  owned: number;
  /** Your top copy's grade or condition. */
  copyLabel: string | null;
}

/** The cards on lists, with your copies and prices. Cards you don't own load from our catalog (not TCG API). */
export function useListItems(productIds: string[]) {
  const store = useStore();
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const byProduct = useMemo(() => {
    const m = new Map<string, HoldingView[]>();
    for (const h of holdings) if (h.quantity > 0) (m.get(h.identity.productId) ?? m.set(h.identity.productId, []).get(h.identity.productId)!).push(h);
    return m;
  }, [holdings]);

  const missingKey = [...new Set(productIds)].filter((id) => !store.data.products[id] && !id.startsWith("sample:")).join(",");
  useEffect(() => {
    if (store.status !== "ready" || !missingKey) return;
    for (const id of missingKey.split(",")) void store.showCatalogProduct(id).catch(() => false);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when the missing set changes
  }, [missingKey, store.status]);

  const info = useCallback(
    (productId: string): ListItemInfo => {
      const copies = [...(byProduct.get(productId) ?? [])].sort((a, b) => (b.price ?? -1) - (a.price ?? -1));
      const top = copies[0];
      const owned = copies.reduce((n, h) => n + h.quantity, 0);
      return {
        productId,
        product: store.data.products[productId] ?? top?.product,
        copies,
        market: top?.price ?? listPrice(store.data.prices, productId, null)?.market ?? null,
        count: Math.max(1, owned),
        owned,
        copyLabel: top ? (top.identity.grade ? `${top.identity.grade.company} ${top.identity.grade.grade}` : top.identity.condition) : null,
      };
    },
    [byProduct, store.data.products, store.data.prices],
  );
  return info;
}

export function listTotals(items: ListItemInfo[], meta: ListMeta) {
  let market = 0;
  let asking = 0;
  let cards = 0;
  for (const i of items) {
    market += (i.market ?? 0) * i.count;
    asking += (askingPrice(meta, i.productId, i.market) ?? 0) * i.count;
    cards += i.count;
  }
  return { market, asking, cards };
}

function newToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(18));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** A list's public link (/l/<token>): the same `share_links` row the app makes (title `list:<id>`). Signed in only. */
export function useListShare(listId: string, open: boolean) {
  const { repoKind, user } = useStore();
  const cloud = repoKind === "cloud" && user ? getBrowserSupabase() : null;
  const [token, setToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !cloud || !user) return;
    let cancelled = false;
    setError(null);
    void (async () => {
      const title = listShareTitle(listId);
      const { data, error: err } = await cloud.from("share_links").select("token").eq("title", title).is("revoked_at", null).limit(1).maybeSingle();
      if (cancelled) return;
      if (err) return setError(err.message);
      if (data?.token) return setToken(data.token);
      const t = newToken();
      const { error: insertErr } = await cloud.from("share_links").insert({ user_id: user.id, token: t, title, show_gains: false });
      if (cancelled) return;
      if (insertErr) setError(insertErr.message);
      else setToken(t);
    })();
    return () => {
      cancelled = true;
    };
  }, [open, cloud, user, listId]);

  const stop = useCallback(async () => {
    if (!cloud) return;
    const { error: err } = await cloud.from("share_links").update({ revoked_at: new Date().toISOString() }).eq("title", listShareTitle(listId)).is("revoked_at", null);
    if (err) throw new Error(err.message);
    setToken(null);
  }, [cloud, listId]);

  return { canShare: Boolean(cloud), token, error, stop };
}
