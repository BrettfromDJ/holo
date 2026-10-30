-- TCG API calls the catalog refresh has made each day, so its many short runs together stay
-- inside a daily budget (and leave the rest of the plan's limit for everything else).
create table if not exists catalog_sync_usage (
  day date primary key,
  calls integer not null default 0
);

-- Server only: no policies, so only the service role can read or write it.
alter table catalog_sync_usage enable row level security;
