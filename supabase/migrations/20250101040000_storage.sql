-- CreateAI Studio - Phase 1
-- A single private bucket holds every user file, namespaced as:
--   {user_id}/avatars/...
--   {user_id}/projects/{project_id}/...
--   {user_id}/generations/{generation_id}/...
--   {user_id}/uploads/...
-- (see lib/core/utils/storage_paths.dart). The bucket is private - nothing
-- is public by default - and access is granted only to the owning user via
-- the folder-name policies below, matching the storage.objects RLS pattern
-- Supabase recommends.

insert into storage.buckets (id, name, public)
values ('app-storage', 'app-storage', false)
on conflict (id) do nothing;

create policy "app_storage_select_own" on storage.objects
  for select using (
    bucket_id = 'app-storage'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "app_storage_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'app-storage'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "app_storage_update_own" on storage.objects
  for update using (
    bucket_id = 'app-storage'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "app_storage_delete_own" on storage.objects
  for delete using (
    bucket_id = 'app-storage'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
