-- Explore brands (Pokémon, Pokémon Japan, Disney Lorcana, …) with their logos.
-- Filled weekly by the catalog sync; read only through server routes.

create table if not exists public.catalog_games (
  slug text primary key,
  name text not null,
  logo_url text,
  image_url text,
  set_count integer,
  card_count integer,
  sort integer not null default 0,
  listed_at timestamptz not null default now()
);

alter table public.catalog_games enable row level security;
