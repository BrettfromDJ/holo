-- Sealed product photos with the white background removed (by Poof), stored once and shown
-- instead of the original on the website and in the app.
alter table products add column if not exists cutout_url text;

insert into storage.buckets (id, name, public)
values ('cutouts', 'cutouts', true)
on conflict (id) do nothing;
