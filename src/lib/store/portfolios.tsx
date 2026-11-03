"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { getBrowserSupabase } from "../supabase/client";
import { applyMainChange, copyTo, filterFor, membersOf as membersIn, moveTo, place as placeIn, type MembershipChange } from "../portfolios";
import type { PortfolioRow } from "../supabase/database.types";
import { useStore } from "./collection-store";
import { useSyncedState } from "./synced-state";

/**
 * A named group of holdings. A holding can be in several; Main is every holding in none of
 * them, plus the ones kept in Main too (user_state `portfolio-main`). See `src/lib/portfolios.ts`.
 */
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
  /** The first portfolio a holding shows in ("main" when it's in Main). */
  portfolioOf(holdingKey: string): string;
  /** Every portfolio a holding shows in, "main" first when it's in Main. */
  membersOf(holdingKey: string): string[];
  nameOf(id: string): string;
  error: string | null;
  create(name: string): Promise<Portfolio>;
  rename(id: string, name: string): Promise<void>;
  remove(id: string): Promise<void>;
  /** Move a holding into a portfolio ("main" takes it out of every custom one). */
  move(holdingKey: string, to: string): Promise<void>;
  /** Move holdings: they end up only in `to`. */
  moveMany(holdingKeys: string[], to: string): Promise<void>;
  /** Copy holdings: they also show in `to`, staying where they are (nothing is duplicated). */
  copyMany(holdingKeys: string[], to: string): Promise<void>;
  /** Put a holding in exactly these portfolios (a slab back from grading joins its raw card's). */
  place(holdingKey: string, ids: string[]): Promise<void>;
}

const NO_KEYS: string[] = [];

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
  // Holdings kept in Main as well as in a named portfolio. Edits replay on the account's list
  // once it's read, so a failed read never saves over it.
  const [mainKeys, setMainKeys] = useSyncedState<string[]>("portfolio-main", NO_KEYS);
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

  const membership = useMemo(() => ({ portfolios, main: mainKeys }), [portfolios, mainKeys]);
  const membersOf = useCallback((key: string) => membersIn(membership, key), [membership]);
  const portfolioOf = useCallback((key: string) => membersIn(membership, key)[0] ?? MAIN, [membership]);

  // A selection that no longer exists falls back to everything.
  const effective = selected === ALL || selected === MAIN || portfolios.some((p) => p.id === selected) ? selected : ALL;

  useEffect(() => {
    setHoldingFilter(filterFor(membership, effective));
  }, [effective, membership, setHoldingFilter]);

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

  const write = useCallback(
    async (change: MembershipChange<Portfolio>) => {
      const changed = new Set(change.changed);
      if (changed.size) {
        await commit(
          change.next.portfolios,
          change.next.portfolios.filter((p) => changed.has(p.id)),
        );
      }
      if (change.mainAdd.length || change.mainRemove.length) setMainKeys((prev) => applyMainChange(prev, change.mainAdd, change.mainRemove));
    },
    [commit, setMainKeys],
  );

  const moveMany = useCallback(async (keys: string[], to: string) => write(moveTo(membership, keys, to)), [membership, write]);
  const copyMany = useCallback(async (keys: string[], to: string) => write(copyTo(membership, keys, to)), [membership, write]);
  const move = useCallback(async (key: string, to: string) => moveMany([key], to), [moveMany]);
  const place = useCallback(async (key: string, ids: string[]) => write(placeIn(membership, new Map([[key, ids]]))), [membership, write]);

  const nameOf = useCallback((id: string) => (id === ALL ? "All portfolios" : id === MAIN ? MAIN_NAME : (portfolios.find((p) => p.id === id)?.name ?? MAIN_NAME)), [portfolios]);

  const value = useMemo(
    () => ({ portfolios, selected: effective, select, portfolioOf, membersOf, nameOf, error, create, rename, remove, move, moveMany, copyMany, place }),
    [portfolios, effective, select, portfolioOf, membersOf, nameOf, error, create, rename, remove, move, moveMany, copyMany, place],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function usePortfolios(): PortfoliosState {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("usePortfolios must be used inside PortfoliosProvider");
  return ctx;
}
