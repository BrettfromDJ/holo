-- Our own price changes for catalog cards (Home's risers). The catalog sync's set pages come
-- without TCG API's 24-hour and 7-day changes, so most cards had none. The sync now keeps each
-- Pokémon card's daily price here (cards from $5, a rolling 9 days) and works out the changes
-- from it. Written and read by the server only.
create table if not exists public.catalog_price_days (
  product_id text not null,
  printing text not null default '',
  day date not null,
  market numeric not null,
  primary key (product_id, printing, day)
);

create index if not exists catalog_price_days_day_idx on public.catalog_price_days (day);

alter table public.catalog_price_days enable row level security;

-- Home's Card of the day reads product_prices ordered by the 24-hour change, from $10.
create index if not exists product_prices_change_24h_idx
  on public.product_prices (change_24h_pct)
  where change_24h_pct is not null and market_price >= 10;
