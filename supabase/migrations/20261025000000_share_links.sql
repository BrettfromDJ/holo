-- Read-only share links for a collection.
-- The public /s/<token> page is rendered on the server with the service role,
-- looks the token up here, and shows only aggregate values and product
-- holdings (never transactions, sources, notes or email). Purchase prices and
-- gains are shown only when show_gains is true.

create table public.share_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  token text not null unique check (char_length(token) >= 20),
  title text check (title is null or char_length(title) <= 80),
  show_gains boolean not null default false,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create index share_links_user on public.share_links (user_id);

alter table public.share_links enable row level security;

create policy "own share links" on public.share_links
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
