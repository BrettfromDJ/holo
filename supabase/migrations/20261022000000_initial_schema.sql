-- Holo: Pokémon collection & investment tracker
-- Initial schema. Apply with `supabase db push` or paste into the SQL editor.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Profiles & preferences
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table public.user_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  currency text not null default 'USD',
  default_view text not null default 'grid' check (default_view in ('grid', 'list')),
  chart_range text not null default '1M' check (chart_range in ('1D', '1W', '1M', '3M', '1Y', 'ALL')),
  updated_at timestamptz not null default now()
);

-- Create a profile + preferences row for every new auth user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  insert into public.user_preferences (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Product catalog cache (shared, written only by the server)
-- ---------------------------------------------------------------------------

-- `id` is `${source}:${external_id}` (e.g. `tcgapi:523161`). Holdings reference
-- this id, so a different pricing source can be added without changing them.
create table public.products (
  id text primary key,
  source text not null,
  external_id text not null,
  name text not null,
  set_name text,
  set_id text,
  number text,
  rarity text,
  product_type text,
  kind text not null check (kind in ('single', 'sealed')),
  image_url text,
  tcgplayer_id bigint,
  tcgplayer_url text,
  printings text[] not null default '{}',
  updated_at timestamptz not null default now(),
  unique (source, external_id)
);

-- Latest known price per product + printing ('' = default printing).
create table public.product_prices (
  product_id text not null references public.products (id) on delete cascade,
  printing text not null default '',
  market_price numeric(12, 2),            -- null = unknown, never zero
  low_price numeric(12, 2),
  change_24h_pct numeric(10, 4),
  change_7d_pct numeric(10, 4),
  change_30d_pct numeric(10, 4),
  source text not null,
  source_updated_at timestamptz,          -- when the source last updated it
  fetched_at timestamptz not null default now(), -- our last successful fetch
  status text not null check (status in ('live', 'stale', 'unavailable')),
  primary key (product_id, printing)
);

-- One observed market price per product/printing/day/source.
create table public.price_snapshots (
  product_id text not null references public.products (id) on delete cascade,
  printing text not null default '',
  snapshot_date date not null,
  market_price numeric(12, 2) not null,
  source text not null,
  captured_at timestamptz not null default now(),
  primary key (product_id, printing, snapshot_date, source)
);

create index price_snapshots_lookup on public.price_snapshots (product_id, printing, snapshot_date desc);

-- ---------------------------------------------------------------------------
-- User collection data
-- ---------------------------------------------------------------------------

-- A holding groups interchangeable units: same product, printing, condition, grade.
create table public.holdings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  product_id text not null references public.products (id),
  printing text,
  condition text not null default 'Near Mint',
  grade_company text,
  grade text,
  -- Manual valuation for graded items (no automated graded pricing yet).
  manual_value numeric(12, 2),
  manual_value_date date,
  notes text,
  created_at timestamptz not null default now(),
  unique nulls not distinct (user_id, product_id, printing, condition, grade_company, grade)
);

create index holdings_user on public.holdings (user_id);

-- Append-only transaction log. Mistakes are fixed with `correction` rows that
-- reference the original (quantity 0 voids it), preserving a full audit trail.
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  holding_id uuid not null references public.holdings (id) on delete cascade,
  type text not null check (type in ('purchase', 'sale', 'adjustment', 'correction')),
  trade_date date not null,
  quantity numeric(12, 4) not null,
  unit_price numeric(12, 4) not null default 0,
  fees numeric(12, 2) not null default 0,
  shipping numeric(12, 2) not null default 0,
  tax numeric(12, 2) not null default 0,
  source text,
  notes text,
  corrects_id uuid references public.transactions (id),
  created_at timestamptz not null default now(),
  check (
    (type in ('purchase', 'sale') and quantity > 0)
    or (type = 'adjustment' and quantity <> 0)
    or (type = 'correction' and corrects_id is not null and quantity >= 0)
  ),
  check (unit_price >= 0 and fees >= 0 and shipping >= 0 and tax >= 0)
);

create index transactions_user_date on public.transactions (user_id, trade_date);
create index transactions_holding on public.transactions (holding_id);

-- Each purchase (or positive adjustment) is a lot. Remaining quantity per lot
-- is derived by FIFO replay in the app (src/lib/finance/ledger.ts), so it can
-- never drift from the transaction log.
create view public.purchase_lots
with (security_invoker = true) as
select
  t.id as lot_id,
  t.user_id,
  t.holding_id,
  h.product_id,
  h.printing,
  h.condition,
  t.trade_date as acquired_on,
  abs(t.quantity) as original_quantity,
  (abs(t.quantity) * t.unit_price + t.fees + t.shipping + t.tax) as total_cost,
  (abs(t.quantity) * t.unit_price + t.fees + t.shipping + t.tax) / abs(t.quantity) as unit_cost
from public.transactions t
join public.holdings h on h.id = t.holding_id
where t.type = 'purchase' or (t.type = 'adjustment' and t.quantity > 0);

-- Daily portfolio snapshot written by the scheduled sync job.
create table public.portfolio_snapshots (
  user_id uuid not null references auth.users (id) on delete cascade,
  snapshot_date date not null,
  market_value numeric(14, 2) not null,
  cost_basis numeric(14, 2) not null,
  unrealized numeric(14, 2) not null,
  market_gain numeric(14, 2) not null,     -- cash-flow-adjusted daily change
  daily_return numeric(14, 8) not null,
  twr_index numeric(18, 8) not null,
  invested numeric(14, 2) not null,
  proceeds numeric(14, 2) not null,
  unpriced_count integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, snapshot_date)
);

create table public.watchlist_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  product_id text not null references public.products (id),
  printing text,
  target_price numeric(12, 2) check (target_price is null or target_price >= 0),
  notes text,
  created_at timestamptz not null default now(),
  unique nulls not distinct (user_id, product_id, printing)
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.products enable row level security;
alter table public.product_prices enable row level security;
alter table public.price_snapshots enable row level security;
alter table public.holdings enable row level security;
alter table public.transactions enable row level security;
alter table public.portfolio_snapshots enable row level security;
alter table public.watchlist_items enable row level security;

-- Profiles & preferences: own row only.
create policy "own profile" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());
create policy "own preferences" on public.user_preferences
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Catalog & prices: readable by signed-in users, written by the service role
-- (server routes / cron), which bypasses RLS.
create policy "catalog readable" on public.products for select to authenticated using (true);
create policy "prices readable" on public.product_prices for select to authenticated using (true);
create policy "snapshots readable" on public.price_snapshots for select to authenticated using (true);

-- Holdings: full access to own rows.
create policy "own holdings select" on public.holdings for select using (user_id = auth.uid());
create policy "own holdings insert" on public.holdings for insert with check (user_id = auth.uid());
create policy "own holdings update" on public.holdings for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Transactions: append-only. No update or delete policies exist.
create policy "own transactions select" on public.transactions for select using (user_id = auth.uid());
create policy "own transactions insert" on public.transactions for insert
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.holdings h where h.id = holding_id and h.user_id = auth.uid())
  );

create policy "own portfolio snapshots" on public.portfolio_snapshots for select using (user_id = auth.uid());

create policy "own watchlist" on public.watchlist_items
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
