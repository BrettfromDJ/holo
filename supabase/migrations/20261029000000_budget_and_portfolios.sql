-- Monthly spending budget, stored with the other preferences.
alter table public.user_preferences add column if not exists monthly_budget numeric(12, 2);

-- Portfolios: named groups of holdings ("Resale inventory", …). A holding
-- belongs to at most one; holdings in none of them make up the default
-- "Main" portfolio. Keys are Holo holding keys (product|printing|condition|grade).
create table if not exists public.portfolios (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  holding_keys text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists portfolios_user on public.portfolios (user_id);

alter table public.portfolios enable row level security;

drop policy if exists "own portfolios" on public.portfolios;
create policy "own portfolios" on public.portfolios
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
