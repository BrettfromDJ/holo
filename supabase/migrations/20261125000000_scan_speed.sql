-- The phone scanner's two slow steps (seconds each, measured on the owner's test scans):
-- 1. Finding cards by collector number ("074/131"): the number column had no index, so every
--    lookup read the whole products table. A trigram index makes `number ilike '074/%'` quick
--    (the website's search benefits too).
create extension if not exists pg_trgm;
create index if not exists products_number_trgm on public.products using gin (number gin_trgm_ops);

-- 2. The scan's picture against every card's fingerprint (/api/scan/match, ~8 s): the fingerprints
--    had no vector index. Vision's fingerprints are 768 numbers; an HNSW index needs that size
--    written on the column, then finds the nearest cards in milliseconds.
alter table public.card_prints alter column print type vector(768);
create index if not exists card_prints_hnsw on public.card_prints using hnsw (print vector_l2_ops);
