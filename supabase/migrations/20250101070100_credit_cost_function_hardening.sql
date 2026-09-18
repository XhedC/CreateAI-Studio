-- CreateAI Studio - Phase 6 follow-up
-- get_credit_cost() only reads `credit_costs`, a table already protected by
-- its own RLS policy (authenticated-only, active rows only) - it never
-- needed SECURITY DEFINER's elevated privilege. Recreating it as SECURITY
-- INVOKER (the default) makes RLS apply based on the actual caller, so an
-- anon caller now transparently gets no rows instead of the function
-- running with elevated rights - this is what the security advisor's
-- "Public/Signed-In Users Can Execute SECURITY DEFINER Function" warnings
-- were flagging in 20250101070000_credits_subscriptions.sql, and this is
-- the correct fix rather than a suppression. Never edit an already-applied
-- migration file - this is a new one, per docs/GITHUB_SUPABASE.md.
create or replace function public.get_credit_cost(p_generation_type text, p_variant text default null)
returns integer
language sql
stable
security invoker
set search_path = public
as $$
  select cost from public.credit_costs
  where generation_type = p_generation_type
    and variant is not distinct from p_variant
    and active = true
  order by created_at desc
  limit 1;
$$;
