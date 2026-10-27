-- Small per-user settings that should follow you across devices: release
-- reminders, the trade in progress, milestones already celebrated, the
-- getting-started checklist. One JSON value per key.

create table if not exists public.user_state (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  key text not null check (char_length(key) between 1 and 64),
  value jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

alter table public.user_state enable row level security;

drop policy if exists "own state" on public.user_state;
create policy "own state" on public.user_state
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
