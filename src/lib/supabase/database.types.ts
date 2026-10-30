/**
 * Typed schema for supabase-js. Mirrors supabase/migrations. Regenerate with:
 *   npx supabase gen types typescript --project-id <id> > src/lib/supabase/database.types.ts
 */
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

type Table<Row, Insert = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Partial<Row>;
  Relationships: [];
};

export type ProductRow = {
  id: string;
  source: string;
  external_id: string;
  name: string;
  set_name: string | null;
  set_id: string | null;
  number: string | null;
  rarity: string | null;
  product_type: string | null;
  kind: "single" | "sealed";
  image_url: string | null;
  /** The sealed photo with its background removed, when one has been made. */
  cutout_url?: string | null;
  tcgplayer_id: number | null;
  tcgplayer_url: string | null;
  printings: string[];
  updated_at: string;
};

export type ProductPriceRow = {
  product_id: string;
  printing: string;
  market_price: number | null;
  low_price: number | null;
  change_24h_pct: number | null;
  change_7d_pct: number | null;
  change_30d_pct: number | null;
  source: string;
  source_updated_at: string | null;
  fetched_at: string;
  status: "live" | "stale" | "unavailable";
};

export type PriceSnapshotRow = {
  product_id: string;
  printing: string;
  snapshot_date: string;
  market_price: number;
  source: string;
  captured_at: string;
};

export type HoldingRow = {
  id: string;
  user_id: string;
  product_id: string;
  printing: string | null;
  condition: string;
  grade_company: string | null;
  grade: string | null;
  manual_value: number | null;
  manual_value_date: string | null;
  notes: string | null;
  created_at: string;
};

export type TransactionRow = {
  id: string;
  user_id: string;
  holding_id: string;
  type: "purchase" | "sale" | "adjustment" | "correction";
  trade_date: string;
  quantity: number;
  unit_price: number;
  fees: number;
  shipping: number;
  tax: number;
  source: string | null;
  notes: string | null;
  corrects_id: string | null;
  created_at: string;
};

export type PortfolioSnapshotRow = {
  user_id: string;
  snapshot_date: string;
  market_value: number;
  cost_basis: number;
  unrealized: number;
  market_gain: number;
  daily_return: number;
  twr_index: number;
  invested: number;
  proceeds: number;
  unpriced_count: number;
  created_at: string;
};

export type WatchlistRow = {
  id: string;
  user_id: string;
  product_id: string;
  printing: string | null;
  target_price: number | null;
  notes: string | null;
  created_at: string;
  /** When the price alert last fired (migration 20261031000000); cleared once the price is back above target. */
  alerted_at?: string | null;
};

/** An iPhone's push token (migration 20261031000000). */
export type DeviceTokenRow = {
  token: string;
  user_id: string;
  environment: "sandbox" | "production";
  updated_at: string;
};

export type PreferencesRow = {
  user_id: string;
  currency: string;
  default_view: "grid" | "list";
  chart_range: "1D" | "1W" | "1M" | "3M" | "1Y" | "ALL";
  updated_at: string;
  monthly_budget?: number | null;
};

export type ShareLinkRow = {
  id: string;
  user_id: string;
  token: string;
  title: string | null;
  show_gains: boolean;
  created_at: string;
  revoked_at: string | null;
};

export type ShelfRow = {
  id: string;
  user_id: string;
  name: string;
  emoji: string | null;
  product_ids: string[];
  created_at: string;
  updated_at: string;
};

export type CatalogSetRow = {
  slug: string;
  tcgapi_id: number;
  game_slug: string;
  game_name: string;
  name: string;
  abbreviation: string | null;
  release_date: string | null;
  card_count: number | null;
  image_url: string | null;
  icon_url: string | null;
  product_count: number | null;
  listed_at: string;
  products_synced_at: string | null;
};

export type CatalogGameRow = {
  slug: string;
  name: string;
  logo_url: string | null;
  image_url: string | null;
  set_count: number | null;
  card_count: number | null;
  sort: number;
  listed_at: string;
};

export type PortfolioRow = {
  id: string;
  user_id: string;
  name: string;
  holding_keys: string[];
  created_at: string;
  updated_at: string;
};

export type UserStateRow = {
  user_id: string;
  key: string;
  value: unknown;
  updated_at: string;
};

export type ProfileRow = {
  id: string;
  display_name: string | null;
  created_at: string;
};

export type Database = {
  public: {
    Tables: {
      profiles: Table<ProfileRow>;
      user_preferences: Table<PreferencesRow>;
      products: Table<ProductRow>;
      product_prices: Table<ProductPriceRow>;
      price_snapshots: Table<PriceSnapshotRow>;
      holdings: Table<HoldingRow>;
      transactions: Table<TransactionRow>;
      portfolio_snapshots: Table<PortfolioSnapshotRow>;
      watchlist_items: Table<WatchlistRow>;
      share_links: Table<ShareLinkRow>;
      shelves: Table<ShelfRow>;
      portfolios: Table<PortfolioRow>;
      user_state: Table<UserStateRow>;
      device_tokens: Table<DeviceTokenRow>;
      catalog_sets: Table<CatalogSetRow>;
      catalog_games: Table<CatalogGameRow>;
    };
    Views: {
      purchase_lots: {
        Row: {
          lot_id: string;
          user_id: string;
          holding_id: string;
          product_id: string;
          printing: string | null;
          condition: string;
          acquired_on: string;
          original_quantity: number;
          total_cost: number;
          unit_cost: number;
        };
        Relationships: [];
      };
    };
    Functions: { [_ in never]: never };
    Enums: { [_ in never]: never };
    CompositeTypes: { [_ in never]: never };
  };
};
