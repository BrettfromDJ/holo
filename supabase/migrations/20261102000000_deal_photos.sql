-- Photos that document deals, taken or attached in the app. Private: each account reads and
-- writes only its own folder ("<user id>/<file>.jpg").
insert into storage.buckets (id, name, public)
values ('deal-photos', 'deal-photos', false)
on conflict (id) do nothing;

create policy "deal photos: read own" on storage.objects for select to authenticated
  using (bucket_id = 'deal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "deal photos: add own" on storage.objects for insert to authenticated
  with check (bucket_id = 'deal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "deal photos: delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'deal-photos' and (storage.foldername(name))[1] = auth.uid()::text);
