-- Custom shelves: user-named groups of products ("Grails", "For sale", …).
-- A shelf only references products; values always come from holdings.

create table public.shelves (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  emoji text check (emoji is null or char_length(emoji) <= 8),
  product_ids text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index shelves_user on public.shelves (user_id);

alter table public.shelves enable row level security;

create policy "own shelves" on public.shelves
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
