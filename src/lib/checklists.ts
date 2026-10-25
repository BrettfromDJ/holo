"use client";

import { useEffect, useState } from "react";
import { compareCollectorNumbers } from "./collector-number";
import type { HoldingView } from "./finance/portfolio";
import type { ChecklistCard, SetChecklist } from "./pricing/types";

const CACHE_PREFIX = "holo:checklist:v1:";
const CACHE_MS = 7 * 24 * 60 * 60 * 1000;

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
    const res = await fetch(`/api/sets/${encodeURIComponent(setId)}`);
    const body = await res.json().catch(() => null);
    if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't load this set's checklist.");
    const checklist = body.checklist as SetChecklist;
    checklist.cards.sort((a, b) => compareCollectorNumbers(a.number, b.number));
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

/** Loads a set's checklist: cached in this browser for a week, one API call per set otherwise. */
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
