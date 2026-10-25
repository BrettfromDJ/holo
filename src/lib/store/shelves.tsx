"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { getBrowserSupabase } from "../supabase/client";
import type { ShelfRow } from "../supabase/database.types";
import { useStore } from "./collection-store";

/** A user-named group of products, e.g. "Grails" or "For sale". */
export interface Shelf {
  id: string;
  name: string;
  productIds: string[];
  createdAt: string;
}

interface ShelvesState {
  shelves: Shelf[];
  /** Set when the cloud table is missing or unreachable. */
  error: string | null;
  create(name: string, productIds?: string[]): Promise<Shelf>;
  update(id: string, patch: Partial<Pick<Shelf, "name">>): Promise<void>;
  remove(id: string): Promise<void>;
  toggle(id: string, productId: string): Promise<void>;
}

const Ctx = createContext<ShelvesState | null>(null);

const DEMO_SEED: Shelf[] = [
  { id: "demo-grails", name: "Grails", productIds: ["sample:umbreon-vmax-alt", "sample:charizard-base", "sample:es-bb"], createdAt: "2026-01-01T00:00:00Z" },
  { id: "demo-xmas", name: "Opening at Christmas", productIds: ["sample:pe-etb", "sample:151-bundle"], createdAt: "2026-01-02T00:00:00Z" },
];

function fromRow(r: ShelfRow): Shelf {
  return { id: r.id, name: r.name, productIds: r.product_ids ?? [], createdAt: r.created_at };
}

function storageKey(kind: string) {
  return `holo:shelves:${kind}`;
}

function readLocal(kind: string): Shelf[] | null {
  try {
    const raw = localStorage.getItem(storageKey(kind));
    return raw ? (JSON.parse(raw) as Shelf[]) : null;
  } catch {
    return null;
  }
}

function writeLocal(kind: string, shelves: Shelf[]) {
  try {
    localStorage.setItem(storageKey(kind), JSON.stringify(shelves));
  } catch {
    // Storage full or blocked — keep working in memory.
  }
}

/**
 * Shelves live next to the collection: in this browser for demo and local
 * collections, and in the `shelves` table (row-level security) when signed in.
 */
export function ShelvesProvider({ children }: { children: ReactNode }) {
  const { status, repoKind, user } = useStore();
  const [shelves, setShelves] = useState<Shelf[]>([]);
  const [error, setError] = useState<string | null>(null);
  const cloud = repoKind === "cloud" && user ? getBrowserSupabase() : null;

  useEffect(() => {
    if (status !== "ready") return;
    setError(null);
    if (!cloud) {
      setShelves(readLocal(repoKind) ?? (repoKind === "demo" ? DEMO_SEED : []));
      return;
    }
    let cancelled = false;
    void cloud
      .from("shelves")
      .select("*")
      .order("created_at")
      .then(({ data, error: err }) => {
        if (cancelled) return;
        if (err) {
          setShelves([]);
          setError(/shelves/.test(err.message) ? "Run supabase/migrations/20261026000000_shelves.sql in Supabase to enable shelves." : err.message);
        } else setShelves((data ?? []).map(fromRow));
      });
    return () => {
      cancelled = true;
    };
  }, [status, repoKind, cloud]);

  const commitLocal = useCallback(
    (next: Shelf[]) => {
      setShelves(next);
      writeLocal(repoKind, next);
    },
    [repoKind],
  );

  const create = useCallback(
    async (name: string, productIds: string[] = []) => {
      if (cloud && user) {
        const { data, error: err } = await cloud.from("shelves").insert({ user_id: user.id, name, product_ids: productIds }).select().single();
        if (err || !data) throw new Error(err?.message ?? "Couldn't create shelf.");
        const shelf = fromRow(data);
        setShelves((s) => [...s, shelf]);
        return shelf;
      }
      const shelf: Shelf = { id: crypto.randomUUID(), name, productIds, createdAt: new Date().toISOString() };
      commitLocal([...shelves, shelf]);
      return shelf;
    },
    [cloud, user, shelves, commitLocal],
  );

  const update = useCallback(
    async (id: string, patch: Partial<Pick<Shelf, "name">>) => {
      if (cloud) {
        const { error: err } = await cloud.from("shelves").update({ ...patch, updated_at: new Date().toISOString() }).eq("id", id);
        if (err) throw new Error(err.message);
        setShelves((s) => s.map((x) => (x.id === id ? { ...x, ...patch } : x)));
        return;
      }
      commitLocal(shelves.map((x) => (x.id === id ? { ...x, ...patch } : x)));
    },
    [cloud, shelves, commitLocal],
  );

  const remove = useCallback(
    async (id: string) => {
      if (cloud) {
        const { error: err } = await cloud.from("shelves").delete().eq("id", id);
        if (err) throw new Error(err.message);
        setShelves((s) => s.filter((x) => x.id !== id));
        return;
      }
      commitLocal(shelves.filter((x) => x.id !== id));
    },
    [cloud, shelves, commitLocal],
  );

  const toggle = useCallback(
    async (id: string, productId: string) => {
      const shelf = shelves.find((x) => x.id === id);
      if (!shelf) return;
      const productIds = shelf.productIds.includes(productId) ? shelf.productIds.filter((p) => p !== productId) : [...shelf.productIds, productId];
      if (cloud) {
        const { error: err } = await cloud.from("shelves").update({ product_ids: productIds, updated_at: new Date().toISOString() }).eq("id", id);
        if (err) throw new Error(err.message);
        setShelves((s) => s.map((x) => (x.id === id ? { ...x, productIds } : x)));
        return;
      }
      commitLocal(shelves.map((x) => (x.id === id ? { ...x, productIds } : x)));
    },
    [cloud, shelves, commitLocal],
  );

  const value = useMemo(() => ({ shelves, error, create, update, remove, toggle }), [shelves, error, create, update, remove, toggle]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useShelves(): ShelvesState {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useShelves must be used inside ShelvesProvider");
  return ctx;
}
