-- Answers from paid TCG API calls (eBay sales, condition prices, live searches) kept for a day
-- in the database, so every server shares them: each one is paid for at most once a day,
-- however many people look. Server only (no policies).
create table if not exists api_cache (
  key text primary key,
  value jsonb not null,
  expires_at timestamptz not null
);
alter table api_cache enable row level security;
create index if not exists api_cache_expires_idx on api_cache (expires_at);

-- How many paid actions (scans, live searches, history loads) each person has used today, so
-- one heavy user can't spend everyone's daily budget. Keyed by user id, or by address when
-- signed out. Server only (no policies).
create table if not exists api_quota (
  who text not null,
  day date not null,
  action text not null,
  count integer not null default 0,
  primary key (who, day, action)
);
alter table api_quota enable row level security;

-- Count one use if it's under the limit, in one step (so two requests at once can't both slip
-- past it). Returns whether it was allowed.
create or replace function take_quota(p_who text, p_action text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  used integer;
begin
  insert into api_quota (who, day, action, count)
  values (p_who, current_date, p_action, 1)
  on conflict (who, day, action) do update set count = api_quota.count + 1
    where api_quota.count < p_limit
  returning count into used;
  return used is not null;
end;
$$;
revoke all on function take_quota(text, text, integer) from public, anon, authenticated;
