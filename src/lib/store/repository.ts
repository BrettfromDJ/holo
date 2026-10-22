"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { buildDemoData } from "../demo/dataset";
import type { Database, HoldingRow } from "../supabase/database.types";
import { loadCollection } from "../supabase/load";
import { transactionFromRow, watchFromRow } from "../supabase/mappers";
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
  type Transaction,
  type WatchlistItem,
} from "../types";

export type RepositoryKind = "demo" | "local" | "cloud";

export type NewTransaction = Omit<Transaction, "id" | "createdAt">;

/**
 * Persistence boundary for a collection. The UI and the financial engine
 * work on `CollectionData`; repositories decide where it lives.
 *
 * - demo:  sample data rebuilt daily + the visitor's sandbox edits (browser).
 * - local: a real collection stored only in this browser (no account needed).
 * - cloud: Supabase, with row-level security.
 */
export interface Repository {
  readonly kind: RepositoryKind;
  load(today: ISODate): Promise<CollectionData>;
  /** Persist catalog info, current prices and history for a product. */
  importProduct(product: Product, prices: NormalizedPrice[], history: Record<string, PricePoint[]>): Promise<void>;
  addTransaction(tx: NewTransaction): Promise<Transaction>;
  addWatch(item: Omit<WatchlistItem, "id" | "addedAt">): Promise<WatchlistItem>;
  updateWatch(id: string, patch: Partial<Pick<WatchlistItem, "targetPrice" | "notes">>): Promise<void>;
  removeWatch(id: string): Promise<void>;
  setManualValue(identity: HoldingIdentity, value: number, date: ISODate): Promise<void>;
  /** Store refreshed prices (and today's snapshot) where the client owns storage. */
  savePrices(prices: NormalizedPrice[], today: ISODate): Promise<void>;
  savePreferences(p: Preferences): Promise<void>;
}

function newId(): string {
  return crypto.randomUUID();
}

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
    // Storage full or blocked — the session keeps working in memory.
  }
}

/* ------------------------------- Local ---------------------------------- */

const LOCAL_KEY = "holo:local:v1";

function emptyData(): CollectionData {
  return { products: {}, transactions: [], watchlist: [], prices: {}, history: {}, manualValues: {}, preferences: DEFAULT_PREFERENCES };
}

function mergeHistory(existing: PricePoint[] | undefined, incoming: PricePoint[]): PricePoint[] {
  const map = new Map((existing ?? []).map((p) => [p.date, p.price]));
  for (const p of incoming) map.set(p.date, p.price);
  return [...map.entries()].sort(([a], [b]) => (a < b ? -1 : 1)).map(([date, price]) => ({ date, price }));
}

function snapshotPrices(data: CollectionData, prices: NormalizedPrice[], today: ISODate) {
  for (const p of prices) {
    const key = priceKey(p.productId, p.printing);
    data.prices[key] = p;
    // Record today's observation as a daily snapshot; never record unknowns.
    if (p.market !== null) data.history[key] = mergeHistory(data.history[key], [{ date: today, price: p.market }]);
  }
}

export class LocalRepository implements Repository {
  readonly kind: RepositoryKind = "local";
  private data: CollectionData = emptyData();

  async load(): Promise<CollectionData> {
    this.data = { ...emptyData(), ...(readJSON<CollectionData>(LOCAL_KEY) ?? {}) };
    return structuredClone(this.data);
  }
  private save() {
    writeJSON(LOCAL_KEY, this.data);
  }
  async importProduct(product: Product, prices: NormalizedPrice[], history: Record<string, PricePoint[]>) {
    this.data.products[product.id] = product;
    for (const p of prices) this.data.prices[priceKey(p.productId, p.printing)] = p;
    for (const [k, pts] of Object.entries(history)) this.data.history[k] = mergeHistory(this.data.history[k], pts);
    this.save();
  }
  async addTransaction(tx: NewTransaction) {
    const t: Transaction = { ...tx, id: newId(), createdAt: new Date().toISOString() };
    this.data.transactions.push(t);
    this.save();
    return t;
  }
  async addWatch(item: Omit<WatchlistItem, "id" | "addedAt">) {
    const w: WatchlistItem = { ...item, id: newId(), addedAt: new Date().toISOString() };
    this.data.watchlist.push(w);
    this.save();
    return w;
  }
  async updateWatch(id: string, patch: Partial<Pick<WatchlistItem, "targetPrice" | "notes">>) {
    this.data.watchlist = this.data.watchlist.map((w) => (w.id === id ? { ...w, ...patch } : w));
    this.save();
  }
  async removeWatch(id: string) {
    this.data.watchlist = this.data.watchlist.filter((w) => w.id !== id);
    this.save();
  }
  async setManualValue(identity: HoldingIdentity, value: number, date: ISODate) {
    this.data.manualValues[holdingKey(identity)] = { value, date };
    this.save();
  }
  async savePrices(prices: NormalizedPrice[], today: ISODate) {
    snapshotPrices(this.data, prices, today);
    this.save();
  }
  async savePreferences(p: Preferences) {
    this.data.preferences = p;
    this.save();
  }
}

/* -------------------------------- Demo ---------------------------------- */

const DEMO_KEY = "holo:demo:v1";

interface DemoOverlay {
  transactions: Transaction[];
  watchAdded: WatchlistItem[];
  watchRemoved: string[];
  watchPatches: Record<string, Partial<WatchlistItem>>;
  manualValues: CollectionData["manualValues"];
  preferences?: Preferences;
}

/**
 * Sample data is regenerated relative to today on every load; the visitor's
 * own sandbox actions are stored as an overlay so they survive reloads. None
 * of this ever touches a real collection.
 */
export class DemoRepository implements Repository {
  readonly kind: RepositoryKind = "demo";
  private overlay: DemoOverlay = { transactions: [], watchAdded: [], watchRemoved: [], watchPatches: {}, manualValues: {} };

  async load(today: ISODate): Promise<CollectionData> {
    this.overlay = { ...this.overlay, ...(readJSON<DemoOverlay>(DEMO_KEY) ?? {}) };
    const base = buildDemoData(today);
    const watchlist = [...base.watchlist, ...this.overlay.watchAdded]
      .filter((w) => !this.overlay.watchRemoved.includes(w.id))
      .map((w) => ({ ...w, ...(this.overlay.watchPatches[w.id] ?? {}) }));
    return {
      ...base,
      transactions: [...base.transactions, ...this.overlay.transactions],
      watchlist,
      manualValues: { ...base.manualValues, ...this.overlay.manualValues },
      preferences: this.overlay.preferences ?? base.preferences,
    };
  }
  private save() {
    writeJSON(DEMO_KEY, this.overlay);
  }
  async importProduct() {
    // Sample catalog is static; nothing to persist.
  }
  async addTransaction(tx: NewTransaction) {
    const t: Transaction = { ...tx, id: `sandbox-${newId()}`, createdAt: new Date().toISOString() };
    this.overlay.transactions.push(t);
    this.save();
    return t;
  }
  async addWatch(item: Omit<WatchlistItem, "id" | "addedAt">) {
    const w: WatchlistItem = { ...item, id: `sandbox-${newId()}`, addedAt: new Date().toISOString() };
    this.overlay.watchAdded.push(w);
    this.save();
    return w;
  }
  async updateWatch(id: string, patch: Partial<Pick<WatchlistItem, "targetPrice" | "notes">>) {
    this.overlay.watchPatches[id] = { ...(this.overlay.watchPatches[id] ?? {}), ...patch };
    this.save();
  }
  async removeWatch(id: string) {
    this.overlay.watchRemoved.push(id);
    this.overlay.watchAdded = this.overlay.watchAdded.filter((w) => w.id !== id);
    this.save();
  }
  async setManualValue(identity: HoldingIdentity, value: number, date: ISODate) {
    this.overlay.manualValues[holdingKey(identity)] = { value, date };
    this.save();
  }
  async savePrices() {
    // Sample prices are generated, never fetched.
  }
  async savePreferences(p: Preferences) {
    this.overlay.preferences = p;
    this.save();
  }

  static reset() {
    try {
      localStorage.removeItem(DEMO_KEY);
    } catch {
      // ignore
    }
  }
}

/* -------------------------------- Cloud --------------------------------- */

export class CloudRepository implements Repository {
  readonly kind: RepositoryKind = "cloud";
  private holdings: HoldingRow[] = [];

  constructor(
    private readonly client: SupabaseClient<Database>,
    private readonly userId: string,
  ) {}

  async load(): Promise<CollectionData> {
    const { holdingRows, ...data } = await loadCollection(this.client);
    this.holdings = holdingRows;
    return data;
  }

  async importProduct() {
    // The server's /api/catalog route writes catalog, prices and history
    // with the service role, so there is nothing to do client-side.
  }

  private async holdingFor(identity: HoldingIdentity): Promise<HoldingRow> {
    const key = holdingKey(identity);
    const existing = this.holdings.find(
      (h) =>
        holdingKey({
          productId: h.product_id,
          printing: h.printing,
          condition: h.condition as HoldingIdentity["condition"],
          grade: h.grade_company && h.grade ? { company: h.grade_company, grade: h.grade } : null,
        }) === key,
    );
    if (existing) return existing;
    const { data, error } = await this.client
      .from("holdings")
      .insert({
        user_id: this.userId,
        product_id: identity.productId,
        printing: identity.printing,
        condition: identity.condition,
        grade_company: identity.grade?.company ?? null,
        grade: identity.grade?.grade ?? null,
      })
      .select()
      .single();
    if (error || !data) throw error ?? new Error("Could not create holding.");
    this.holdings.push(data);
    return data;
  }

  async addTransaction(tx: NewTransaction): Promise<Transaction> {
    const holding = await this.holdingFor(tx);
    const { data, error } = await this.client
      .from("transactions")
      .insert({
        user_id: this.userId,
        holding_id: holding.id,
        type: tx.type,
        trade_date: tx.date,
        quantity: tx.quantity,
        unit_price: tx.unitPrice,
        fees: tx.fees,
        shipping: tx.shipping,
        tax: tx.tax,
        source: tx.source ?? null,
        notes: tx.notes ?? null,
        corrects_id: tx.correctsId ?? null,
      })
      .select()
      .single();
    if (error || !data) throw error ?? new Error("Could not save transaction.");
    return transactionFromRow(data, holding);
  }

  async addWatch(item: Omit<WatchlistItem, "id" | "addedAt">) {
    const { data, error } = await this.client
      .from("watchlist_items")
      .insert({ user_id: this.userId, product_id: item.productId, printing: item.printing, target_price: item.targetPrice, notes: item.notes ?? null })
      .select()
      .single();
    if (error || !data) throw error ?? new Error("Could not add to watchlist.");
    return watchFromRow(data);
  }

  async updateWatch(id: string, patch: Partial<Pick<WatchlistItem, "targetPrice" | "notes">>) {
    const update: Database["public"]["Tables"]["watchlist_items"]["Update"] = {};
    if ("targetPrice" in patch) update.target_price = patch.targetPrice ?? null;
    if ("notes" in patch) update.notes = patch.notes ?? null;
    const { error } = await this.client.from("watchlist_items").update(update).eq("id", id);
    if (error) throw error;
  }

  async removeWatch(id: string) {
    const { error } = await this.client.from("watchlist_items").delete().eq("id", id);
    if (error) throw error;
  }

  async setManualValue(identity: HoldingIdentity, value: number, date: ISODate) {
    const holding = await this.holdingFor(identity);
    const { error } = await this.client.from("holdings").update({ manual_value: value, manual_value_date: date }).eq("id", holding.id);
    if (error) throw error;
  }

  async savePrices() {
    // Prices and snapshots are written server-side (catalog import, price
    // refresh route and the daily cron) with the service role.
  }

  async savePreferences(p: Preferences) {
    const { error } = await this.client
      .from("user_preferences")
      .upsert({ user_id: this.userId, currency: p.currency, default_view: p.defaultView, chart_range: p.chartRange, updated_at: new Date().toISOString() });
    if (error) throw error;
  }
}
