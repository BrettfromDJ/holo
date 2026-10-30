import { holdingKey, type Condition, type HoldingIdentity, type NormalizedPrice, type Product, type Transaction, type WatchlistItem } from "../types";
import type { HoldingRow, ProductPriceRow, ProductRow, TransactionRow, WatchlistRow } from "./database.types";

const num = (v: number | string | null): number | null => (v === null ? null : Number(v));

export function productFromRow(r: ProductRow): Product {
  return {
    id: r.id,
    source: r.source as Product["source"],
    externalId: r.external_id,
    name: r.name,
    setName: r.set_name,
    setId: r.set_id,
    number: r.number,
    rarity: r.rarity,
    productType: r.product_type,
    kind: r.kind,
    imageUrl: r.image_url,
    tcgplayerId: r.tcgplayer_id,
    tcgplayerUrl: r.tcgplayer_url,
    printings: r.printings ?? [],
  };
}

export function productToRow(p: Product): Omit<ProductRow, "updated_at"> & { updated_at?: string } {
  return {
    id: p.id,
    source: p.source,
    external_id: p.externalId,
    name: p.name,
    set_name: p.setName,
    set_id: p.setId,
    number: p.number,
    rarity: p.rarity,
    product_type: p.productType,
    kind: p.kind,
    image_url: p.imageUrl,
    tcgplayer_id: p.tcgplayerId,
    tcgplayer_url: p.tcgplayerUrl,
    printings: p.printings ?? [],
    updated_at: new Date().toISOString(),
  };
}

export function priceFromRow(r: ProductPriceRow): NormalizedPrice {
  return {
    productId: r.product_id,
    printing: r.printing === "" ? null : r.printing,
    market: num(r.market_price),
    low: num(r.low_price),
    change24hPct: num(r.change_24h_pct),
    change7dPct: num(r.change_7d_pct),
    change30dPct: num(r.change_30d_pct),
    updatedAt: r.source_updated_at,
    fetchedAt: r.fetched_at,
    source: r.source as NormalizedPrice["source"],
    status: r.status,
  };
}

export function priceToRow(p: NormalizedPrice): ProductPriceRow {
  return {
    product_id: p.productId,
    printing: p.printing ?? "",
    market_price: p.market,
    low_price: p.low,
    change_24h_pct: p.change24hPct,
    change_7d_pct: p.change7dPct,
    change_30d_pct: p.change30dPct,
    source: p.source,
    source_updated_at: p.updatedAt,
    fetched_at: p.fetchedAt ?? new Date().toISOString(),
    status: p.status,
  };
}

export function identityFromHolding(h: HoldingRow): HoldingIdentity {
  return {
    productId: h.product_id,
    printing: h.printing,
    condition: h.condition as Condition,
    grade: h.grade_company && h.grade ? { company: h.grade_company, grade: h.grade } : null,
  };
}

export function transactionFromRow(r: TransactionRow, holding: HoldingRow): Transaction {
  return {
    ...identityFromHolding(holding),
    id: r.id,
    type: r.type,
    date: r.trade_date,
    quantity: Number(r.quantity),
    unitPrice: Number(r.unit_price),
    fees: Number(r.fees),
    shipping: Number(r.shipping),
    tax: Number(r.tax),
    source: r.source,
    notes: r.notes,
    correctsId: r.corrects_id,
    createdAt: r.created_at,
  };
}

export function watchFromRow(r: WatchlistRow): WatchlistItem {
  return {
    id: r.id,
    productId: r.product_id,
    printing: r.printing,
    targetPrice: num(r.target_price),
    notes: r.notes,
    addedAt: r.created_at,
  };
}

export function holdingKeyFromRow(h: HoldingRow): string {
  return holdingKey(identityFromHolding(h));
}
