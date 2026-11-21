-- Card artists (illustrators), from the free Pokémon TCG API (pokemontcg.io), matched to our
-- cards by set and number once per set (src/lib/server/artists.ts). Shown on the card page and
-- on each artist's page.
alter table public.products add column if not exists artist text;
create index if not exists products_artist on public.products (lower(artist)) where artist is not null;

alter table public.catalog_sets add column if not exists artists_synced_at timestamptz;
