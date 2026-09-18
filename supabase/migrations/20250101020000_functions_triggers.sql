-- CreateAI Studio - Phase 1
-- updated_at maintenance + new-user bootstrap.

-- ---------------------------------------------------------------------------
-- Generic updated_at trigger
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger set_updated_at before update on public.projects
  for each row execute function public.set_updated_at();

create trigger set_updated_at before update on public.user_usage
  for each row execute function public.set_updated_at();

create trigger set_updated_at before update on public.subscriptions
  for each row execute function public.set_updated_at();

create trigger set_updated_at before update on public.user_settings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- New user bootstrap: whenever a Supabase Auth user is created, seed their
-- profile, default settings, and a free-tier subscription so the app never
-- has to special-case a "no row yet" state on first login.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (user_id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');

  insert into public.user_settings (user_id)
  values (new.id);

  insert into public.subscriptions (user_id, plan_name, status, credits_limit, credits_used)
  values (new.id, 'free', 'active', 50, 0);

  insert into public.user_usage (user_id, period_start, period_end)
  values (
    new.id,
    date_trunc('month', now()),
    date_trunc('month', now()) + interval '1 month' - interval '1 second'
  );

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
