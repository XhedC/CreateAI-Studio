-- CreateAI Studio - Phase 1
-- Fixes found by Supabase's security advisor after the initial schema pass.

-- Pin search_path on the trigger function (mutable search_path lint).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- handle_new_user must run as SECURITY DEFINER (it writes cross-user
-- default rows via the auth.users trigger), but it must never be callable
-- directly via PostgREST's auto-exposed RPC endpoint.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
