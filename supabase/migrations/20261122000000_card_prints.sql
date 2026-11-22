-- Picture fingerprints for every card (Apple Vision feature prints, revision 2), made each night
-- on a Mac by the GitHub "Card fingerprints" workflow (ios/scripts/fingerprints.swift) and sent to
-- /api/fingerprints. The scanner sends a scan's fingerprint to /api/scan/match, which finds the
-- closest cards here. Needs the pgvector extension (Supabase has it).
create extension if not exists vector;

create table if not exists public.card_prints (
  product_id text primary key references public.products (id) on delete cascade,
  image_url text not null,
  print vector not null,
  revision int not null default 2,
  updated_at timestamptz not null default now()
);
alter table public.card_prints enable row level security;

-- Cards still to fingerprint: Pokémon singles with a picture and no fingerprint yet, or whose
-- picture changed since; not oversized.
create or replace function public.card_prints_todo(lim int)
returns table (product_id text, image_url text)
language sql stable as $$
  select p.id, p.image_url
  from public.products p
  join public.catalog_sets s on s.slug = p.set_id
  left join public.card_prints c on c.product_id = p.id
  where p.kind = 'single'
    and p.image_url is not null
    and s.game_name ilike '%pok%'
    and p.name !~* '(over-?\s?sized?|\mjumbo\M)'
    and (c.product_id is null or c.image_url is distinct from p.image_url)
  limit lim
$$;

-- The closest cards to a scan's fingerprint (straight-line distance, as Vision measures it).
create or replace function public.match_card_prints(query vector, k int)
returns table (product_id text, distance double precision)
language sql stable as $$
  select c.product_id, c.print <-> query as distance
  from public.card_prints c
  order by c.print <-> query
  limit k
$$;
