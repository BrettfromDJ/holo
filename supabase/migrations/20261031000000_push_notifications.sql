-- Push notifications for the iPhone app: each phone's APNs token, and when a
-- watched card last triggered its price alert (so it alerts once per drop).

create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- "sandbox" for Xcode builds, "production" for TestFlight and the App Store.
  environment text not null default 'production' check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "own devices" on public.device_tokens;
create policy "own devices" on public.device_tokens
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Set when the alert is sent; cleared when the price goes back above the target.
alter table public.watchlist_items add column if not exists alerted_at timestamptz;
