"use client";

import { useEffect, useState } from "react";
import { compareCollectorNumbers } from "./collector-number";
import type { HoldingView } from "./finance/portfolio";
import type { ExploreProduct, ExploreSet } from "./explore/types";
import type { ChecklistCard, SetChecklist } from "./pricing/types";

const CACHE_PREFIX = "holo:checklist:v1:";
const CACHE_MS = 24 * 60 * 60 * 1000;

/**
 * SAMPLE checklist sizes for the demo sets (cards in the set incl. secret
 * rares). Demo binders show numbered empty slots only — never invented names.
 */
const SAMPLE_SET_SIZES: Record<string, number> = {
  "evolving-skies": 237,
  "scarlet-violet-151": 207,
  "surging-sparks": 252,
  "lost-origin": 247,
  "base-set": 102,
  "obsidian-flames": 230,
  "silver-tempest": 245,
  "fusion-strike": 284,
  "crown-zenith": 230,
  "paldean-fates": 245,
  "prismatic-evolutions": 180,
};

/** A set the user owns singles from. */
export interface OwnedSet {
  setId: string;
  name: string;
  sample: boolean;
  holdings: HoldingView[];
}

/** Singles (raw or graded) grouped by set, most owned first. */
export function ownedSets(holdings: HoldingView[]): OwnedSet[] {
  const map = new Map<string, OwnedSet>();
  for (const h of holdings) {
    const p = h.product;
    if (!p || p.kind !== "single" || !p.setId) continue;
    const set = map.get(p.setId) ?? { setId: p.setId, name: p.setName ?? p.setId, sample: p.source === "sample", holdings: [] };
    set.holdings.push(h);
    map.set(p.setId, set);
  }
  return [...map.values()].sort((a, b) => b.holdings.length - a.holdings.length || a.name.localeCompare(b.name));
}

function leadingNumber(n: string | null): number | null {
  const m = n?.match(/\d+/);
  return m ? Number(m[0]) : null;
}

function sampleChecklist(set: OwnedSet): SetChecklist | null {
  const size = SAMPLE_SET_SIZES[set.setId];
  if (!size) return null;
  const cards: ChecklistCard[] = Array.from({ length: size }, (_, i) => ({
    productId: `sample-slot:${set.setId}:${i + 1}`,
    number: String(i + 1),
    name: `#${i + 1}`,
    rarity: null,
    imageUrl: null,
    market: null,
  }));
  for (const h of set.holdings) {
    const n = leadingNumber(h.product?.number ?? null);
    if (n && n >= 1 && n <= size) {
      cards[n - 1] = { productId: h.identity.productId, number: h.product!.number, name: h.product!.name, rarity: h.product!.rarity, imageUrl: h.product!.imageUrl, market: h.price };
    }
  }
  return { setId: set.setId, name: set.name, releaseDate: null, iconUrl: null, cards };
}

function readCache(setId: string): SetChecklist | null {
  try {
    const raw = localStorage.getItem(CACHE_PREFIX + setId);
    if (!raw) return null;
    const { at, checklist } = JSON.parse(raw) as { at: number; checklist: SetChecklist };
    return Date.now() - at < CACHE_MS ? checklist : null;
  } catch {
    return null;
  }
}

function writeCache(checklist: SetChecklist) {
  try {
    localStorage.setItem(CACHE_PREFIX + checklist.setId, JSON.stringify({ at: Date.now(), checklist }));
  } catch {
    // Storage full — the checklist is refetched next time.
  }
}

const inflight = new Map<string, Promise<SetChecklist>>();

async function fetchChecklist(setId: string): Promise<SetChecklist> {
  const existing = inflight.get(setId);
  if (existing) return existing;
  const p = (async () => {
    // Read from the stored Explore catalog — no TCG API requests.
    const res = await fetch(`/api/explore/sets/${encodeURIComponent(setId)}`);
    const body = (await res.json().catch(() => null)) as { set?: ExploreSet; products?: ExploreProduct[]; error?: { message?: string } } | null;
    if (!res.ok || !body?.set) throw new Error(res.status === 404 ? "This set isn't in Holo's catalog yet." : (body?.error?.message ?? "Couldn't load this set's checklist."));
    if (!body.set.loaded) throw new Error("This set's card list loads in an upcoming daily catalog sync.");
    const checklist: SetChecklist = {
      setId,
      name: body.set.name,
      releaseDate: body.set.releaseDate,
      iconUrl: body.set.iconUrl,
      cards: (body.products ?? [])
        .filter((p) => p.product.kind === "single")
        .map((p) => ({ productId: p.product.id, number: p.product.number, name: p.product.name, rarity: p.product.rarity, imageUrl: p.product.imageUrl, market: p.market }))
        .sort((a, b) => compareCollectorNumbers(a.number, b.number)),
    };
    writeCache(checklist);
    return checklist;
  })();
  inflight.set(setId, p);
  try {
    return await p;
  } finally {
    inflight.delete(setId);
  }
}

export interface ChecklistState {
  checklist: SetChecklist | null;
  loading: boolean;
  error: string | null;
  /** True for demo sets, whose empty slots are numbered placeholders. */
  sample: boolean;
}

/** Loads a set's checklist from the stored catalog, cached in this browser for a day. */
export function useChecklist(set: OwnedSet | null): ChecklistState {
  const [state, setState] = useState<ChecklistState>({ checklist: null, loading: false, error: null, sample: false });
  const setId = set?.setId ?? null;
  const sample = set?.sample ?? false;

  useEffect(() => {
    if (!set) return setState({ checklist: null, loading: false, error: null, sample: false });
    if (set.sample) return setState({ checklist: sampleChecklist(set), loading: false, error: null, sample: true });
    const cachedList = readCache(set.setId);
    if (cachedList) return setState({ checklist: cachedList, loading: false, error: null, sample: false });
    let cancelled = false;
    setState({ checklist: null, loading: true, error: null, sample: false });
    fetchChecklist(set.setId).then(
      (checklist) => !cancelled && setState({ checklist, loading: false, error: null, sample: false }),
      (err: Error) => !cancelled && setState({ checklist: null, loading: false, error: err.message, sample: false }),
    );
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- keyed by set id; holdings changes are handled below
  }, [setId, sample]);

  // Demo checklists embed owned cards, so rebuild when holdings change.
  useEffect(() => {
    if (set?.sample) setState((s) => ({ ...s, checklist: sampleChecklist(set) }));
  }, [set]);

  return state;
}

/** Owned product ids within a checklist. */
export function ownedIn(checklist: SetChecklist, set: OwnedSet): Set<string> {
  const ids = new Set(set.holdings.map((h) => h.identity.productId));
  return new Set(checklist.cards.filter((c) => ids.has(c.productId)).map((c) => c.productId));
}

/**
 * Checklists for several sets at once (the Master Sets list), keyed by set id. Each comes from
 * this browser's day-long cache or the stored catalog — never the TCG API.
 */
export function useChecklists(sets: OwnedSet[]): Record<string, ChecklistState> {
  const [states, setStates] = useState<Record<string, ChecklistState>>({});
  const key = sets.map((s) => `${s.setId}:${s.sample ? 1 : 0}`).join("|");

  useEffect(() => {
    let cancelled = false;
    const next: Record<string, ChecklistState> = {};
    const todo: OwnedSet[] = [];
    for (const set of sets) {
      if (set.sample) next[set.setId] = { checklist: sampleChecklist(set), loading: false, error: null, sample: true };
      else {
        const cached = readCache(set.setId);
        if (cached) next[set.setId] = { checklist: cached, loading: false, error: null, sample: false };
        else {
          next[set.setId] = { checklist: null, loading: true, error: null, sample: false };
          todo.push(set);
        }
      }
    }
    setStates(next);
    for (const set of todo) {
      fetchChecklist(set.setId).then(
        (checklist) => !cancelled && setStates((s) => ({ ...s, [set.setId]: { checklist, loading: false, error: null, sample: false } })),
        (err: Error) => !cancelled && setStates((s) => ({ ...s, [set.setId]: { checklist: null, loading: false, error: err.message, sample: false } })),
      );
    }
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- keyed by the sets' ids; demo holdings changes are handled below
  }, [key]);

  // Demo checklists embed owned cards, so rebuild them when holdings change.
  useEffect(() => {
    if (!sets.some((s) => s.sample)) return;
    setStates((prev) => {
      const out = { ...prev };
      for (const set of sets) if (set.sample) out[set.setId] = { checklist: sampleChecklist(set), loading: false, error: null, sample: true };
      return out;
    });
  }, [sets]);

  return states;
}
