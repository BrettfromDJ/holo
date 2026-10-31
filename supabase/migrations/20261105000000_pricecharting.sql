-- PriceCharting's price guide, downloaded once a day (one file per brand): ungraded and graded
-- values for every card that has a TCGplayer id, which is how it's matched to the catalog
-- (products.tcgplayer_id = tcg_id). Public market data; server writes, anyone may read.
create table if not exists pricecharting_prices (
  pc_id bigint primary key,
  tcg_id bigint,
  console_name text,
  product_name text,
  ungraded numeric,
  grade_7 numeric,
  grade_8 numeric,
  grade_9 numeric,
  grade_9_5 numeric,
  psa_10 numeric,
  bgs_10 numeric,
  cgc_10 numeric,
  sgc_10 numeric,
  sales_volume integer,
  updated_at timestamptz not null default now()
);
create index if not exists pricecharting_prices_tcg_idx on pricecharting_prices (tcg_id);
alter table pricecharting_prices enable row level security;
drop policy if exists "pricecharting prices are public" on pricecharting_prices;
create policy "pricecharting prices are public" on pricecharting_prices for select using (true);
