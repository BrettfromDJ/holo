-- Explore's "Trending this week" and "Biggest drops" read product_prices ordered by the 7-day
-- change, among prices of $5 or more. This index keeps that a short index scan.
create index if not exists product_prices_change_7d_idx
  on public.product_prices (change_7d_pct)
  where change_7d_pct is not null and market_price >= 5;
