-- Explore catalog: every set across Holo's catalogs, filled gradually by the
-- daily catalog sync (a few sets per day, within the TCG API budget). Products
-- and their prices reuse public.products / public.product_prices.
-- Read only through server routes (service role), so no policies are needed.

create table public.catalog_sets (
  slug text primary key,
  tcgapi_id bigint not null,
  game_slug text not null,
  game_name text not null,
  name text not null,
  abbreviation text,
  release_date date,
  card_count integer,
  image_url text,
  icon_url text,
  product_count integer,
  listed_at timestamptz not null default now(),
  products_synced_at timestamptz
);

create index catalog_sets_game on public.catalog_sets (game_slug, release_date desc);
create index catalog_sets_sync on public.catalog_sets (products_synced_at nulls first, release_date desc);

alter table public.catalog_sets enable row level security;

-- Fast name search across the catalog.
create extension if not exists pg_trgm;
create index if not exists products_name_trgm on public.products using gin (name gin_trgm_ops);
create index if not exists products_set on public.products (set_id);
