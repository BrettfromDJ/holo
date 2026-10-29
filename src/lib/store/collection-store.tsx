"use client";

import { ebayGradedTargets, withEbayGradedPrices, withSampleGradedPrices } from "@/lib/graded";
import { loadEbay } from "@/lib/ebay-client";
import type { EbaySales } from "@/lib/ebay-types";
import { mapLimit } from "@/lib/pricing/cache";
import type { User } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { looksSealed } from "../catalog";
import { SAMPLE_BY_ID } from "../demo/catalog";
import { todayISO } from "../finance/dates";
import { computeHoldings, computeTimeline, summarize, totalRealized, type HoldingView, type PortfolioSummary, type TimelinePoint } from "../finance/portfolio";
import type { RealizedEntry } from "../finance/ledger";
import type { SearchHit } from "../pricing/types";
import { getBrowserSupabase } from "../supabase/client";
import { isSupabaseConfigured } from "../supabase/config";
import {
  DEFAULT_PREFERENCES,
  holdingKey,
  priceKey,
  type CollectionData,
  type HoldingIdentity,
  type ISODate,
  type NormalizedPrice,
  type PricePoint,
  type Preferences,
  type Product,
  type ProductKind,
  type Transaction,
  type WatchlistItem,
} from "../types";
import { CloudRepository, DemoRepository, LocalRepository, type NewTransaction, type Repository, type RepositoryKind } from "./repository";

export type AppMode = "demo" | "personal";

export interface IntegrationStatus {
  tcgapi: boolean;
  supabase: boolean;
}

export interface ImportedProduct {
  product: Product;
  prices: NormalizedPrice[];
  history: Record<string, PricePoint[]>;
  historyAvailable: boolean;
  historyReason: string | null;
}

interface StoreState {
  status: "loading" | "ready" | "error";
  error: string | null;
  mode: AppMode;
  repoKind: RepositoryKind;
  today: ISODate;
  data: CollectionData;
  user: User | null;
  integrations: IntegrationStatus;
  pricesRefreshedAt: string | null;
  refreshing: boolean;
  priceError: string | null;
  /** When set, portfolio views (usePortfolio) only include holdings it accepts. */
  holdingFilter: ((holdingKey: string) => boolean) | null;
}

export interface AddOptions {
  productId?: string;
  /** Add to the watchlist instead of the collection. */
  watch?: boolean;
  /** Remove this watchlist item once the purchase is saved. */
  fromWatchId?: string;
  /** Open straight to the form for a product not yet in the collection's catalog. */
  hit?: SearchHit;
}

interface StoreActions {
  setMode(mode: AppMode): void;
  /** Limit portfolio views to some holdings (e.g. one portfolio), or null for all. */
  setHoldingFilter(filter: ((holdingKey: string) => boolean) | null): void;
  importProduct(productId: string, printing?: string | null, kind?: ProductKind): Promise<ImportedProduct>;
  setProductKind(productId: string, kind: ProductKind): Promise<void>;
  /** Load a stored catalog product for viewing (no TCG API requests). Nothing is saved to the collection. Returns false if it isn't in the catalog. */
  showCatalogProduct(productId: string): Promise<boolean>;
  /** Merge price history points into the in-memory history. */
  mergeHistory(productId: string, printing: string | null, points: PricePoint[]): void;
  addTransaction(tx: NewTransaction): Promise<Transaction>;
  addWatch(productId: string, printing: string | null, targetPrice: number | null): Promise<void>;
  updateWatch(id: string, patch: Partial<Pick<WatchlistItem, "targetPrice" | "notes">>): Promise<void>;
  removeWatch(id: string): Promise<void>;
  /** `null` clears the manual valuation (back to the graded market price). */
  setManualValue(identity: HoldingIdentity, value: number | null): Promise<void>;
  refreshPrices(force?: boolean): Promise<void>;
  savePreferences(p: Partial<Preferences>): Promise<void>;
  resetDemo(): Promise<void>;
  signOut(): Promise<void>;
  openAdd(opts?: AddOptions): void;
  closeAdd(): void;
  addTarget: { open: boolean } & AddOptions;
}

/** Merge price points into history, one point per date, oldest first. */
function mergeInto(data: CollectionData, history: Record<string, PricePoint[]>) {
  for (const [k, pts] of Object.entries(history)) {
    const merged = new Map((data.history[k] ?? []).map((x) => [x.date, x.price]));
    for (const x of pts) merged.set(x.date, x.price);
    data.history[k] = [...merged.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([date, price]) => ({ date, price }));
  }
}

const StoreContext = createContext<(StoreState & StoreActions) | null>(null);

const MODE_KEY = "holo:mode";
const REFRESH_KEY = "holo:prices-refreshed";
const ATTEMPT_KEY = "holo:prices-attempted";

function emptyData(): CollectionData {
  return {
    products: {},
    transactions: [],
    watchlist: [],
    prices: {},
    history: {},
    manualValues: {},
    preferences: DEFAULT_PREFERENCES,
  };
}

async function fetchJSON<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const body = await res.json().catch(() => null);
  if (!res.ok) throw new Error(body?.error?.message ?? `Request failed (${res.status})`);
  return body as T;
}

export function CollectionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<StoreState>(() => ({
    status: "loading",
    error: null,
    mode: "demo",
    repoKind: "demo",
    today: todayISO(),
    data: emptyData(),
    user: null,
    holdingFilter: null,
    integrations: { tcgapi: false, supabase: isSupabaseConfigured() },
    pricesRefreshedAt: null,
    refreshing: false,
    priceError: null,
  }));
  const [addTarget, setAddTarget] = useState<StoreActions["addTarget"]>({ open: false });
  const repoRef = useRef<Repository>(new DemoRepository());
  const loadSeq = useRef(0);

  const load = useCallback(async (mode: AppMode) => {
    const seq = ++loadSeq.current;
    setState((s) => ({ ...s, status: "loading", error: null, mode }));
    try {
      const supabase = getBrowserSupabase();
      const user = supabase ? (await supabase.auth.getUser()).data.user : null;
      let repo: Repository;
      if (mode === "demo") repo = new DemoRepository();
      else if (supabase && user) repo = new CloudRepository(supabase, user.id);
      else repo = new LocalRepository();
      repoRef.current = repo;
      const today = todayISO();
      const data = await repo.load(today);
      if (seq !== loadSeq.current) return;
      let refreshedAt: string | null = null;
      try {
        refreshedAt = localStorage.getItem(`${REFRESH_KEY}:${repo.kind}`);
      } catch {
        // ignore
      }
      setState((s) => ({ ...s, status: "ready", data, today, user, repoKind: repo.kind, pricesRefreshedAt: refreshedAt }));
    } catch (err) {
      if (seq !== loadSeq.current) return;
      setState((s) => ({ ...s, status: "error", error: err instanceof Error ? err.message : "Could not load your collection." }));
    }
  }, []);

  // Initial mode: remembered choice, else personal when signed in, else demo.
  useEffect(() => {
    let mode: AppMode | null = null;
    try {
      mode = localStorage.getItem(MODE_KEY) as AppMode | null;
    } catch {
      // ignore
    }
    (async () => {
      if (!mode) {
        const supabase = getBrowserSupabase();
        const user = supabase ? (await supabase.auth.getSession()).data.session?.user : null;
        mode = user ? "personal" : "demo";
      }
      void load(mode);
    })();
    fetchJSON<{ tcgapi: { configured: boolean }; supabase: { configured: boolean } }>("/api/status")
      .then((s) => setState((st) => ({ ...st, integrations: { tcgapi: s.tcgapi.configured, supabase: s.supabase.configured } })))
      .catch(() => undefined);

    const supabase = getBrowserSupabase();
    const sub = supabase?.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_IN" || event === "SIGNED_OUT") {
        let m: AppMode = event === "SIGNED_IN" ? "personal" : "demo";
        try {
          m = (localStorage.getItem(MODE_KEY) as AppMode | null) ?? m;
        } catch {
          // ignore
        }
        void load(m);
      }
    });
    return () => sub?.data.subscription.unsubscribe();
  }, [load]);

  const setMode = useCallback(
    (mode: AppMode) => {
      try {
        localStorage.setItem(MODE_KEY, mode);
      } catch {
        // ignore
      }
      void load(mode);
    },
    [load],
  );

  const importProduct = useCallback(
    async (productId: string, printing?: string | null, kind?: ProductKind): Promise<ImportedProduct> => {
      if (productId.startsWith("sample:")) {
        if (state.mode !== "demo") throw new Error("Sample products can only be used in demo mode.");
        const p = SAMPLE_BY_ID[productId];
        if (!p) throw new Error("Unknown sample product.");
        const key = priceKey(p.id, p.printings?.[0] ?? null);
        return {
          product: state.data.products[productId],
          prices: state.data.prices[key] ? [state.data.prices[key]] : [],
          history: { [key]: state.data.history[key] ?? [] },
          historyAvailable: true,
          historyReason: null,
        };
      }
      if (state.mode === "demo") throw new Error("Demo mode only uses sample products. Switch to your collection to add real products.");
      const res = await fetchJSON<{ product: Product; prices: NormalizedPrice[]; history: PricePoint[]; historyAvailable: boolean; historyReason: string | null }>(
        "/api/catalog",
        { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ productId, printing: printing ?? null, kind: kind ?? null }) },
      );
      const histPrinting = printing ?? res.prices[0]?.printing ?? null;
      const history = { [priceKey(res.product.id, histPrinting)]: res.history };
      await repoRef.current.importProduct(res.product, res.prices, history);
      setState((s) => {
        const data = { ...s.data, products: { ...s.data.products, [res.product.id]: res.product }, prices: { ...s.data.prices }, history: { ...s.data.history } };
        for (const p of res.prices) data.prices[priceKey(p.productId, p.printing)] = p;
        for (const [k, pts] of Object.entries(history)) {
          const merged = new Map((data.history[k] ?? []).map((x) => [x.date, x.price]));
          for (const x of pts) merged.set(x.date, x.price);
          data.history[k] = [...merged.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([date, price]) => ({ date, price }));
        }
        return { ...s, data };
      });
      return { product: res.product, prices: res.prices, history, historyAvailable: res.historyAvailable, historyReason: res.historyReason };
    },
    [state.mode, state.data],
  );

  const showCatalogProduct = useCallback(async (productId: string) => {
    const res = await fetch(`/api/explore/products/${encodeURIComponent(productId)}`);
    if (!res.ok) return false;
    const body = (await res.json()) as { product: Product; prices: NormalizedPrice[]; history: Record<string, PricePoint[]> };
    setState((s) => {
      const data = { ...s.data, products: { ...s.data.products, [body.product.id]: s.data.products[body.product.id] ?? body.product }, prices: { ...s.data.prices }, history: { ...s.data.history } };
      for (const p of body.prices) data.prices[priceKey(p.productId, p.printing)] ??= p;
      mergeInto(data, body.history);
      return { ...s, data };
    });
    return true;
  }, []);

  const mergeHistory = useCallback((productId: string, printing: string | null, points: PricePoint[]) => {
    setState((s) => {
      const data = { ...s.data, history: { ...s.data.history } };
      mergeInto(data, { [priceKey(productId, printing)]: points });
      return { ...s, data };
    });
  }, []);

  // Stable, so effects that set the filter don't re-run on every store update.
  const setHoldingFilter = useCallback((filter: ((holdingKey: string) => boolean) | null) => setState((s) => ({ ...s, holdingFilter: filter })), []);

  const setProductKind = useCallback(async (productId: string, kind: ProductKind) => {
    await repoRef.current.setProductKind(productId, kind);
    setState((s) => {
      const p = s.data.products[productId];
      return p ? { ...s, data: { ...s.data, products: { ...s.data.products, [productId]: { ...p, kind } } } } : s;
    });
  }, []);

  const addTransaction = useCallback(async (tx: NewTransaction) => {
    const saved = await repoRef.current.addTransaction(tx);
    setState((s) => ({ ...s, data: { ...s.data, transactions: [...s.data.transactions, saved] } }));
    return saved;
  }, []);

  const addWatch = useCallback(async (productId: string, printing: string | null, targetPrice: number | null) => {
    const w = await repoRef.current.addWatch({ productId, printing, targetPrice });
    setState((s) => ({ ...s, data: { ...s.data, watchlist: [...s.data.watchlist, w] } }));
  }, []);

  const updateWatch = useCallback(async (id: string, patch: Partial<Pick<WatchlistItem, "targetPrice" | "notes">>) => {
    await repoRef.current.updateWatch(id, patch);
    setState((s) => ({ ...s, data: { ...s.data, watchlist: s.data.watchlist.map((w) => (w.id === id ? { ...w, ...patch } : w)) } }));
  }, []);

  const removeWatch = useCallback(async (id: string) => {
    await repoRef.current.removeWatch(id);
    setState((s) => ({ ...s, data: { ...s.data, watchlist: s.data.watchlist.filter((w) => w.id !== id) } }));
  }, []);

  const setManualValue = useCallback(
    async (identity: HoldingIdentity, value: number | null) => {
      const today = state.today;
      await repoRef.current.setManualValue(identity, value, today);
      setState((s) => {
        const manualValues = { ...s.data.manualValues };
        if (value === null) delete manualValues[holdingKey(identity)];
        else manualValues[holdingKey(identity)] = { value, date: today };
        return { ...s, data: { ...s.data, manualValues } };
      });
    },
    [state.today],
  );

  const refreshPrices = useCallback(
    async (force = false) => {
      const repo = repoRef.current;
      if (repo.kind === "demo" || !state.integrations.tcgapi) return;
      // Automatic refreshes happen at most once per calendar day; the Refresh button forces one.
      const lastDay = state.pricesRefreshedAt ? todayISO(new Date(state.pricesRefreshedAt)) : null;
      let attempted: string | null = null;
      try {
        attempted = localStorage.getItem(`${ATTEMPT_KEY}:${repo.kind}`);
      } catch {
        // ignore
      }
      if (!force && (lastDay === state.today || attempted === state.today)) return;
      const ids = [...new Set([...state.data.transactions.map((t) => t.productId), ...state.data.watchlist.map((w) => w.productId)])].filter((id) =>
        id.startsWith("tcgapi:"),
      );
      if (!ids.length) return;
      setState((s) => ({ ...s, refreshing: true, priceError: null }));
      try {
        const res = await fetchJSON<{ prices: NormalizedPrice[]; failed: { id: string; code: string }[] }>("/api/tcg/prices", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ ids }),
        });
        await repo.savePrices(res.prices, state.today);
        const now = new Date().toISOString();
        try {
          localStorage.setItem(`${REFRESH_KEY}:${repo.kind}`, now);
        } catch {
          // ignore
        }
        setState((s) => {
          const prices = { ...s.data.prices };
          const history = { ...s.data.history };
          for (const p of res.prices) {
            const key = priceKey(p.productId, p.printing);
            prices[key] = p;
            if (p.market !== null) {
              const pts = (history[key] ?? []).filter((x) => x.date !== s.today);
              history[key] = [...pts, { date: s.today, price: p.market }];
            }
          }
          // Products that failed keep their last known price, marked stale.
          for (const f of res.failed) {
            for (const [k, p] of Object.entries(prices)) if (p.productId === f.id && p.status === "live") prices[k] = { ...p, status: "stale" };
          }
          return {
            ...s,
            refreshing: false,
            pricesRefreshedAt: now,
            priceError: res.failed.length ? `${res.failed.length} product${res.failed.length === 1 ? "" : "s"} couldn't be refreshed.` : null,
            data: { ...s.data, prices, history },
          };
        });
      } catch (err) {
        // Remember today's failed automatic attempt so it isn't retried on every
        // page load — without claiming the prices were refreshed.
        if (!force) {
          try {
            localStorage.setItem(`${ATTEMPT_KEY}:${repo.kind}`, state.today);
          } catch {
            // ignore
          }
        }
        setState((s) => ({ ...s, refreshing: false, priceError: err instanceof Error ? err.message : "Price refresh failed." }));
      }
    },
    [state.integrations.tcgapi, state.pricesRefreshedAt, state.data.transactions, state.data.watchlist, state.today],
  );

  // Refresh prices automatically (at most once a day) when a personal collection loads.
  useEffect(() => {
    if (state.status === "ready" && state.mode === "personal") void refreshPrices(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.status, state.mode, state.integrations.tcgapi]);

  // One-time repair: products saved before sealed detection improved (e.g.
  // "Illustration Collection" boxes) may be stored as singles. Runs once per
  // repository so a later manual choice in the type menu is never overridden.
  useEffect(() => {
    if (state.status !== "ready" || state.mode !== "personal") return;
    const doneKey = `holo:kindfix:v1:${state.repoKind}`;
    try {
      if (localStorage.getItem(doneKey)) return;
    } catch {
      return;
    }
    const wrong = Object.values(state.data.products).filter((p) => p.kind === "single" && looksSealed(p.name));
    void (async () => {
      let ok = true;
      for (const p of wrong) {
        try {
          await setProductKind(p.id, "sealed");
        } catch {
          ok = false;
        }
      }
      try {
        if (ok) localStorage.setItem(doneKey, "1");
      } catch {
        // ignore
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.status, state.mode, state.repoKind]);

  const savePreferences = useCallback(
    async (p: Partial<Preferences>) => {
      const next = { ...state.data.preferences, ...p };
      setState((s) => ({ ...s, data: { ...s.data, preferences: next } }));
      await repoRef.current.savePreferences(next);
    },
    [state.data.preferences],
  );

  const resetDemo = useCallback(async () => {
    DemoRepository.reset();
    await load("demo");
  }, [load]);

  const signOut = useCallback(async () => {
    const supabase = getBrowserSupabase();
    await supabase?.auth.signOut();
    try {
      localStorage.removeItem(MODE_KEY);
    } catch {
      // ignore
    }
    await load("demo");
  }, [load]);

  const value = useMemo(
    () => ({
      ...state,
      setMode,
      importProduct,
      setProductKind,
      showCatalogProduct,
      mergeHistory,
      setHoldingFilter,
      addTransaction,
      addWatch,
      updateWatch,
      removeWatch,
      setManualValue,
      refreshPrices,
      savePreferences,
      resetDemo,
      signOut,
      addTarget,
      openAdd: (opts?: AddOptions) => setAddTarget({ open: true, ...opts }),
      closeAdd: () => setAddTarget({ open: false }),
    }),
    [state, setMode, importProduct, setProductKind, showCatalogProduct, mergeHistory, setHoldingFilter, addTransaction, addWatch, updateWatch, removeWatch, setManualValue, refreshPrices, savePreferences, resetDemo, signOut, addTarget],
  );

  // Portfolio math (holdings, timeline, realized) is computed once per data
  // change here and shared, instead of once per component that shows numbers.
  // Slabs are valued from recent eBay sales for their grade. Each product held
  // graded is loaded once (cached for 12 hours on the server, CDN and device).
  const [ebayGraded, setEbayGraded] = useState<Record<string, EbaySales | null>>({});
  const gradedTargets = useMemo(() => (state.status === "ready" ? ebayGradedTargets(state.data) : []), [state.status, state.data]);
  useEffect(() => {
    const todo = gradedTargets.filter((t) => !(priceKey(t.productId, t.printing) in ebayGraded));
    if (!todo.length) return;
    let cancelled = false;
    void mapLimit(todo, 2, async (t) => {
      const value = await loadEbay(t.productId, t.printing).catch(() => null);
      if (!cancelled) setEbayGraded((m) => ({ ...m, [priceKey(t.productId, t.printing)]: value }));
    });
    return () => {
      cancelled = true;
    };
  }, [gradedTargets, ebayGraded]);

  const allView = useMemo(() => portfolioView(state.data, state.today, ebayGraded), [state.data, state.today, ebayGraded]);
  const filtered = state.holdingFilter;
  const filteredView = useMemo(
    () => (filtered ? portfolioView({ ...state.data, transactions: state.data.transactions.filter((t) => filtered(holdingKey(t))) }, state.today, ebayGraded) : allView),
    [state.data, state.today, filtered, allView, ebayGraded],
  );
  const views = useMemo(() => ({ all: allView, filtered: filteredView }), [allView, filteredView]);

  return (
    <StoreContext.Provider value={value}>
      <PortfolioViewContext.Provider value={views}>{children}</PortfolioViewContext.Provider>
    </StoreContext.Provider>
  );
}

export function useStore() {
  const ctx = useContext(StoreContext);
  if (!ctx) throw new Error("useStore must be used within CollectionProvider");
  return ctx;
}

export interface PortfolioView {
  holdings: HoldingView[];
  summary: PortfolioSummary;
  timeline: TimelinePoint[];
  realized: RealizedEntry[];
}

function portfolioView(raw: CollectionData, today: ISODate, ebay: Record<string, EbaySales | null>): PortfolioView {
  // Slabs: real ones from eBay sales for their grade, demo ones from the sample curve.
  const data = withSampleGradedPrices(withEbayGradedPrices(raw, ebay, today), today);
  const holdings = computeHoldings(data, today);
  const realized = totalRealized(data, today);
  return { holdings, summary: summarize(holdings, realized.total), timeline: computeTimeline(data, today), realized: realized.entries };
}

const PortfolioViewContext = createContext<{ all: PortfolioView; filtered: PortfolioView } | null>(null);

/** Holdings, summary and timeline — limited to the selected portfolio unless `ignoreFilter`. Computed once in the provider. */
export function usePortfolio(opts?: { ignoreFilter?: boolean }): PortfolioView {
  const views = useContext(PortfolioViewContext);
  if (!views) throw new Error("usePortfolio must be used inside CollectionProvider");
  return opts?.ignoreFilter ? views.all : views.filtered;
}
