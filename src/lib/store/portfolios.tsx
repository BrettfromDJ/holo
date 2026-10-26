"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { getBrowserSupabase } from "../supabase/client";
import type { PortfolioRow } from "../supabase/database.types";
import { useStore } from "./collection-store";

/** A named group of holdings. Holdings in no portfolio belong to "Main". */
export interface Portfolio {
  id: string;
  name: string;
  holdingKeys: string[];
}

export const MAIN = "main";
export const ALL = "all";
export const MAIN_NAME = "Main";

interface PortfoliosState {
  portfolios: Portfolio[];
  /** "all", "main", or a portfolio id. */
  selected: string;
  select(id: string): void;
  /** Portfolio id a holding belongs to ("main" when none). */
  portfolioOf(holdingKey: string): string;
  nameOf(id: string): string;
  error: string | null;
  create(name: string): Promise<Portfolio>;
  rename(id: string, name: string): Promise<void>;
  remove(id: string): Promise<void>;
  /** Move a holding into a portfolio ("main" takes it out of every custom one). */
  move(holdingKey: string, to: string): Promise<void>;
}

const Ctx = createContext<PortfoliosState | null>(null);

function fromRow(r: PortfolioRow): Portfolio {
  return { id: r.id, name: r.name, holdingKeys: r.holding_keys ?? [] };
}

const storageKey = (kind: string) => `holo:portfolios:${kind}`;
const selectedKey = (kind: string) => `holo:portfolio-selected:${kind}`;

function readJSON<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

function writeJSON(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Storage full or blocked — keep working in memory.
  }
}

/**
 * Portfolios live in this browser for demo/local collections and in the
 * `portfolios` table when signed in. The selected portfolio filters every
 * portfolio view (Overview, Collection, Gains, Analytics) through the store.
 */
export function PortfoliosProvider({ children }: { children: ReactNode }) {
  const { status, repoKind, user, setHoldingFilter } = useStore();
  const [portfolios, setPortfolios] = useState<Portfolio[]>([]);
  const [selected, setSelected] = useState<string>(ALL);
  const [error, setError] = useState<string | null>(null);
  const cloud = repoKind === "cloud" && user ? getBrowserSupabase() : null;

  useEffect(() => {
    if (status !== "ready") return;
    setError(null);
    setSelected(readJSON<string>(selectedKey(repoKind)) ?? ALL);
    if (!cloud) {
      setPortfolios(readJSON<Portfolio[]>(storageKey(repoKind)) ?? []);
      return;
    }
    let cancelled = false;
    void cloud
      .from("portfolios")
      .select("*")
      .order("created_at")
      .then(({ data, error: err }) => {
        if (cancelled) return;
        if (err) {
          setPortfolios([]);
          setError(/portfolios/.test(err.message) ? "Run supabase/migrations/20261029000000_budget_and_portfolios.sql in Supabase to enable portfolios." : err.message);
        } else setPortfolios((data ?? []).map(fromRow));
      });
    return () => {
      cancelled = true;
    };
  }, [status, repoKind, cloud]);

  const owner = useMemo(() => {
    const map = new Map<string, string>();
    for (const p of portfolios) for (const k of p.holdingKeys) map.set(k, p.id);
    return map;
  }, [portfolios]);
  const portfolioOf = useCallback((key: string) => owner.get(key) ?? MAIN, [owner]);

  // A selection that no longer exists falls back to everything.
  const effective = selected === ALL || selected === MAIN || portfolios.some((p) => p.id === selected) ? selected : ALL;

  useEffect(() => {
    if (effective === ALL) setHoldingFilter(null);
    else setHoldingFilter((key: string) => (owner.get(key) ?? MAIN) === effective);
  }, [effective, owner, setHoldingFilter]);

  const select = useCallback(
    (id: string) => {
      setSelected(id);
      writeJSON(selectedKey(repoKind), id);
    },
    [repoKind],
  );

  const commit = useCallback(
    async (next: Portfolio[], changed: Portfolio[]) => {
      if (cloud) {
        for (const p of changed) {
          const { error: err } = await cloud.from("portfolios").update({ name: p.name, holding_keys: p.holdingKeys, updated_at: new Date().toISOString() }).eq("id", p.id);
          if (err) throw new Error(err.message);
        }
      } else writeJSON(storageKey(repoKind), next);
      setPortfolios(next);
    },
    [cloud, repoKind],
  );

  const create = useCallback(
    async (name: string) => {
      if (cloud && user) {
        const { data, error: err } = await cloud.from("portfolios").insert({ user_id: user.id, name, holding_keys: [] }).select().single();
        if (err || !data) throw new Error(err?.message ?? "Couldn't create portfolio.");
        const p = fromRow(data);
        setPortfolios((s) => [...s, p]);
        return p;
      }
      const p: Portfolio = { id: crypto.randomUUID(), name, holdingKeys: [] };
      await commit([...portfolios, p], []);
      return p;
    },
    [cloud, user, portfolios, commit],
  );

  const rename = useCallback(
    async (id: string, name: string) => {
      const next = portfolios.map((p) => (p.id === id ? { ...p, name } : p));
      await commit(
        next,
        next.filter((p) => p.id === id),
      );
    },
    [portfolios, commit],
  );

  const remove = useCallback(
    async (id: string) => {
      if (cloud) {
        const { error: err } = await cloud.from("portfolios").delete().eq("id", id);
        if (err) throw new Error(err.message);
        setPortfolios((s) => s.filter((p) => p.id !== id));
      } else await commit(portfolios.filter((p) => p.id !== id), []);
      if (selected === id) select(ALL);
    },
    [cloud, portfolios, commit, selected, select],
  );

  const move = useCallback(
    async (holdingKey: string, to: string) => {
      const next = portfolios.map((p) => {
        const has = p.holdingKeys.includes(holdingKey);
        if (p.id === to && !has) return { ...p, holdingKeys: [...p.holdingKeys, holdingKey] };
        if (p.id !== to && has) return { ...p, holdingKeys: p.holdingKeys.filter((k) => k !== holdingKey) };
        return p;
      });
      await commit(
        next,
        next.filter((p, i) => p !== portfolios[i]),
      );
    },
    [portfolios, commit],
  );

  const nameOf = useCallback((id: string) => (id === ALL ? "All portfolios" : id === MAIN ? MAIN_NAME : (portfolios.find((p) => p.id === id)?.name ?? MAIN_NAME)), [portfolios]);

  const value = useMemo(
    () => ({ portfolios, selected: effective, select, portfolioOf, nameOf, error, create, rename, remove, move }),
    [portfolios, effective, select, portfolioOf, nameOf, error, create, rename, remove, move],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function usePortfolios(): PortfoliosState {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("usePortfolios must be used inside PortfoliosProvider");
  return ctx;
}
