-- CreateAI Studio - Phase 1
-- Row Level Security. Every user-owned table is locked to auth.uid() for
-- select/insert/update/delete. No policy uses `using (true)` - there is no
-- public-read requirement yet in Phase 1.

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.generations enable row level security;
alter table public.generation_files enable row level security;
alter table public.user_usage enable row level security;
alter table public.credit_transactions enable row level security;
alter table public.subscriptions enable row level security;
alter table public.user_settings enable row level security;
alter table public.notifications enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = user_id);
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = user_id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "profiles_delete_own" on public.profiles
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- projects
-- ---------------------------------------------------------------------------
create policy "projects_select_own" on public.projects
  for select using (auth.uid() = user_id);
create policy "projects_insert_own" on public.projects
  for insert with check (auth.uid() = user_id);
create policy "projects_update_own" on public.projects
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "projects_delete_own" on public.projects
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- generations
-- ---------------------------------------------------------------------------
create policy "generations_select_own" on public.generations
  for select using (auth.uid() = user_id);
create policy "generations_insert_own" on public.generations
  for insert with check (auth.uid() = user_id);
create policy "generations_update_own" on public.generations
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "generations_delete_own" on public.generations
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- generation_files
-- ---------------------------------------------------------------------------
create policy "generation_files_select_own" on public.generation_files
  for select using (auth.uid() = user_id);
create policy "generation_files_insert_own" on public.generation_files
  for insert with check (auth.uid() = user_id);
create policy "generation_files_update_own" on public.generation_files
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "generation_files_delete_own" on public.generation_files
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_usage (read-only from the client; writes happen via trusted backend
-- code/Edge Functions using the service role, so no insert/update policy is
-- granted to authenticated users)
-- ---------------------------------------------------------------------------
create policy "user_usage_select_own" on public.user_usage
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- credit_transactions (read-only from the client; balances are only ever
-- mutated by trusted backend code)
-- ---------------------------------------------------------------------------
create policy "credit_transactions_select_own" on public.credit_transactions
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- subscriptions (read-only from the client; plan changes happen via a
-- trusted backend flow once payments are implemented)
-- ---------------------------------------------------------------------------
create policy "subscriptions_select_own" on public.subscriptions
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_settings
-- ---------------------------------------------------------------------------
create policy "user_settings_select_own" on public.user_settings
  for select using (auth.uid() = user_id);
create policy "user_settings_insert_own" on public.user_settings
  for insert with check (auth.uid() = user_id);
create policy "user_settings_update_own" on public.user_settings
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- notifications (read + mark-as-read only; notifications are created by
-- trusted backend code)
-- ---------------------------------------------------------------------------
create policy "notifications_select_own" on public.notifications
  for select using (auth.uid() = user_id);
create policy "notifications_update_own" on public.notifications
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "notifications_delete_own" on public.notifications
  for delete using (auth.uid() = user_id);
