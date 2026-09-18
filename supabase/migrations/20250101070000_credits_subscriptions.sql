-- CreateAI Studio - Phase 6
-- Credits, usage tracking, and subscription/monetization foundation.
--
-- Reuses (extends, never duplicates) Phase 1's existing `subscriptions` and
-- `credit_transactions` tables rather than introducing a parallel
-- `credit_balances` table - `subscriptions.credits_limit`/`credits_used`
-- already IS the balance mechanism the whole app (CreditsRepository,
-- every generate-* Edge Function) reads today, and splitting that into a
-- second table would only create two sources of truth to keep in sync.
-- Every existing column/value used by Phase 1-5 code is left untouched -
-- see docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md for the full design writeup.
--
-- Safe to run: every table this migration touches currently has 0 rows in
-- this project (dev, pre-launch), so widening a CHECK constraint or adding
-- a nullable/defaulted column here cannot violate existing data.

-- ---------------------------------------------------------------------------
-- plans - configurable plan definitions (replaces hard-coding plan limits
-- in Flutter or in Edge Functions). Publicly readable (it's shared,
-- non-sensitive reference data); never client-writable.
-- ---------------------------------------------------------------------------
create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code in ('free', 'pro', 'business')),
  name text not null,
  description text,
  monthly_credits integer not null check (monthly_credits >= 0),
  price_display text not null default 'Pricing coming soon',
  active boolean not null default true,
  features jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_plans_code on public.plans (code);

create trigger set_updated_at before update on public.plans
  for each row execute function public.set_updated_at();

-- Seed the three initial plans. `monthly_credits` for 'free' matches the
-- value Phase 1's handle_new_user() already hard-coded (50), so wiring the
-- trigger to read from this table below changes nothing for existing
-- behavior. Pro/Business figures are explicit placeholders, NOT final
-- pricing - see the brief's "do not assume these prices are final".
insert into public.plans (code, name, description, monthly_credits, price_display, features)
values
  ('free', 'Free', 'Get started with AI generation at no cost.', 50,
   'Free', jsonb_build_object('max_projects', 10, 'priority_support', false)),
  ('pro', 'Pro', 'More credits and priority support for regular creators.', 500,
   'Pricing coming soon', jsonb_build_object('max_projects', 100, 'priority_support', true)),
  ('business', 'Business', 'The most credits, for teams and heavy usage.', 2000,
   'Pricing coming soon', jsonb_build_object('max_projects', null, 'priority_support', true, 'team_seats', true))
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- subscriptions - extended, not replaced. New columns are additive and
-- nullable/defaulted so every existing read (`select credits_limit,
-- credits_used ...`) keeps working unchanged.
-- ---------------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists plan_id uuid references public.plans (id),
  add column if not exists provider text,
  add column if not exists provider_subscription_id text,
  add column if not exists current_period_start timestamptz,
  add column if not exists current_period_end timestamptz,
  add column if not exists cancel_at_period_end boolean not null default false,
  add column if not exists lifetime_credits_earned integer not null default 0,
  add column if not exists lifetime_credits_used integer not null default 0;

-- Backfill plan_id for any pre-existing rows from their plan_name string
-- (a no-op today since this project has 0 subscription rows, but correct
-- and safe if ever run against a project that already has data).
update public.subscriptions s
set plan_id = p.id
from public.plans p
where s.plan_id is null and p.code = s.plan_name;

-- Widen the status vocabulary (adds 'trialing'/'paused'; keeps every
-- existing value - 'active' in particular is depended on by every
-- generate-* Edge Function's credits check, and is left exactly as-is).
alter table public.subscriptions drop constraint if exists subscriptions_status_check;
alter table public.subscriptions add constraint subscriptions_status_check
  check (status in ('active', 'trialing', 'past_due', 'cancelled', 'expired', 'paused'));

-- `provider` is intentionally unconstrained (free text) rather than an
-- enum - the brief requires the architecture to support adding future
-- payment providers (Google Play Billing, web payments, ...) without a
-- schema change; validating known values, if ever needed, belongs in
-- application code, not a CHECK constraint that would need a migration
-- every time a provider is added.

create index if not exists idx_subscriptions_plan_id on public.subscriptions (plan_id);
create index if not exists idx_subscriptions_current_period_end
  on public.subscriptions (current_period_end);

-- ---------------------------------------------------------------------------
-- credit_transactions - extended, not replaced. `user_id`/`amount`/
-- `created_at` and the table's own name/shape are unchanged.
-- ---------------------------------------------------------------------------
alter table public.credit_transactions
  add column if not exists balance_after integer,
  add column if not exists reference_type text,
  add column if not exists idempotency_key text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

-- Replace the old lowercase vocabulary with the brief's explicit type list.
-- Safe: 0 existing rows in this project, and every write path (the four
-- generate-* Edge Functions) is updated in this same phase to use the new
-- values - see docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
alter table public.credit_transactions drop constraint if exists credit_transactions_transaction_type_check;
alter table public.credit_transactions add constraint credit_transactions_transaction_type_check
  check (transaction_type in (
    'MONTHLY_GRANT', 'GENERATION_CHARGE', 'REFUND', 'MANUAL_ADJUSTMENT',
    'PURCHASE', 'SUBSCRIPTION_GRANT', 'EXPIRATION', 'PROMOTIONAL_CREDIT'
  ));

create unique index if not exists idx_credit_transactions_idempotency_key
  on public.credit_transactions (user_id, idempotency_key)
  where idempotency_key is not null;
create index if not exists idx_credit_transactions_reference
  on public.credit_transactions (reference_type, reference_id);

-- ---------------------------------------------------------------------------
-- credit_costs - configurable, server-trusted cost per generation type.
-- Publicly readable (so the Flutter UI can show "Generate Video - 30
-- credits" before submitting), never client-writable. `variant` is
-- nullable to represent a flat/default cost (every type uses this today);
-- a future per-quality/per-duration cost is a new row, not a schema change.
-- ---------------------------------------------------------------------------
create table if not exists public.credit_costs (
  id uuid primary key default gen_random_uuid(),
  generation_type text not null check (generation_type in ('text', 'image', 'music', 'video', 'funnel')),
  variant text,
  cost integer not null check (cost >= 0),
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_credit_costs_type_variant
  on public.credit_costs (generation_type, coalesce(variant, ''));
create index if not exists idx_credit_costs_active on public.credit_costs (active);

create trigger set_updated_at before update on public.credit_costs
  for each row execute function public.set_updated_at();

-- Seed with the EXACT values every Edge Function already hard-codes today
-- (image is cost-per-image, multiplied client-side by numberOfImages,
-- exactly like the current AI_IMAGE settings flow) - moving them here
-- changes nothing about current behavior, only where the number lives.
insert into public.credit_costs (generation_type, variant, cost, metadata)
values
  ('image', null, 1, jsonb_build_object('note', 'per image; multiplied by numberOfImages (1-4)')),
  ('music', null, 3, '{}'::jsonb),
  ('video', null, 5, '{}'::jsonb),
  ('funnel', null, 4, '{}'::jsonb)
on conflict (generation_type, coalesce(variant, '')) do nothing;

-- ---------------------------------------------------------------------------
-- usage_records - one row per billable generation event (detail log).
-- Distinct from Phase 1's `user_usage` (a per-month aggregate counter
-- table that no code ever populated) - this is the actual ledger the
-- Usage Dashboard/History screens query in Phase 6; `user_usage` is left
-- untouched rather than removed, per "do not delete existing".
-- ---------------------------------------------------------------------------
create table if not exists public.usage_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  generation_id uuid not null unique references public.generations (id) on delete cascade,
  project_id uuid references public.projects (id) on delete set null,
  generation_type text not null check (generation_type in ('text', 'image', 'music', 'video', 'funnel')),
  credits_consumed integer not null default 0 check (credits_consumed >= 0),
  status text not null default 'processing'
    check (status in ('processing', 'completed', 'failed', 'refunded')),
  provider text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_usage_records_user_id on public.usage_records (user_id);
create index if not exists idx_usage_records_project_id on public.usage_records (project_id);
create index if not exists idx_usage_records_generation_type on public.usage_records (generation_type);
create index if not exists idx_usage_records_created_at on public.usage_records (created_at);
create index if not exists idx_usage_records_user_created on public.usage_records (user_id, created_at desc);

create trigger set_updated_at before update on public.usage_records
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- idempotency_keys - the shared mechanism reserve_credits()/
-- refund_generation_credits()/grant_monthly_credits() all use to guarantee
-- "this exact operation happens at most once". No client access at all -
-- RLS is enabled with zero policies, so only service-role (Edge Functions)
-- or the SECURITY DEFINER functions below can touch it.
-- ---------------------------------------------------------------------------
create table if not exists public.idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  key text not null,
  operation text not null,
  status text not null default 'in_progress' check (status in ('in_progress', 'completed', 'failed')),
  generation_id uuid references public.generations (id) on delete set null,
  result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, key, operation)
);

create index if not exists idx_idempotency_keys_generation_id
  on public.idempotency_keys (generation_id);

create trigger set_updated_at before update on public.idempotency_keys
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- billing_events - provider webhook/event log for the future payment
-- integration (see docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md's provider
-- abstraction). Nothing writes to this yet in Phase 6 - no payment
-- provider is connected - but the table exists so that integration is a
-- new Edge Function, not a new migration.
-- ---------------------------------------------------------------------------
create table if not exists public.billing_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  event_id text not null,
  event_type text not null,
  user_id uuid references auth.users (id) on delete set null,
  subscription_id uuid references public.subscriptions (id) on delete set null,
  processed boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (provider, event_id)
);

create index if not exists idx_billing_events_user_id on public.billing_events (user_id);
create index if not exists idx_billing_events_subscription_id on public.billing_events (subscription_id);
create index if not exists idx_billing_events_processed on public.billing_events (processed);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.plans enable row level security;
alter table public.credit_costs enable row level security;
alter table public.usage_records enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.billing_events enable row level security;

-- plans / credit_costs: shared, non-sensitive reference data - readable by
-- any authenticated user, writable only by trusted backend code (no
-- insert/update/delete policy is granted here at all).
create policy "plans_select_active" on public.plans
  for select to authenticated using (active = true);
create policy "credit_costs_select_active" on public.credit_costs
  for select to authenticated using (active = true);

-- usage_records: read-only, own rows only.
create policy "usage_records_select_own" on public.usage_records
  for select using (auth.uid() = user_id);

-- billing_events: read-only, own rows only (a user's own billing history).
create policy "billing_events_select_own" on public.billing_events
  for select using (auth.uid() = user_id);

-- idempotency_keys: intentionally NO policies at all beyond RLS being
-- enabled - this table is pure internal plumbing for the billing
-- functions below; there is no legitimate reason for a client to read or
-- write it directly.

-- ---------------------------------------------------------------------------
-- Billing functions - SECURITY DEFINER so they can atomically touch
-- subscriptions/credit_transactions/usage_records/idempotency_keys
-- regardless of the calling role's own RLS grants, but EXECUTE is revoked
-- from anon/authenticated below so a client can NEVER call these directly
-- via PostgREST RPC - only Edge Functions using the service-role key can,
-- exactly like this project's existing handle_new_user() pattern.
-- ---------------------------------------------------------------------------

create or replace function public.get_credit_cost(p_generation_type text, p_variant text default null)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select cost from public.credit_costs
  where generation_type = p_generation_type
    and variant is not distinct from p_variant
    and active = true
  order by created_at desc
  limit 1;
$$;

-- Atomically reserves (charges) credits for one generation. Race-safe via
-- a single conditional UPDATE (Postgres row-locks the matching row for the
-- duration of the UPDATE, so two concurrent calls for the same user
-- serialize instead of both reading a stale balance) and idempotent via
-- `idempotency_keys` (the caller passes the generation's own id as the
-- key, so a retried/duplicated Edge Function invocation for the same
-- generation charges at most once).
create or replace function public.reserve_credits(
  p_user_id uuid,
  p_amount integer,
  p_idempotency_key text,
  p_generation_id uuid,
  p_generation_type text,
  p_project_id uuid default null,
  p_provider text default null,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing record;
  v_balance_after integer;
  v_tx_id uuid;
begin
  if p_amount <= 0 then
    return jsonb_build_object('success', false, 'code', 'INVALID_AMOUNT', 'error', 'Amount must be positive.');
  end if;

  select * into v_existing from public.idempotency_keys
    where user_id = p_user_id and key = p_idempotency_key and operation = 'reserve_credits';

  if found then
    if v_existing.status = 'completed' then
      return v_existing.result;
    elsif v_existing.status = 'in_progress' then
      return jsonb_build_object('success', false, 'code', 'DUPLICATE_REQUEST', 'error', 'This request is already being processed.');
    else
      return coalesce(v_existing.result, jsonb_build_object('success', false, 'code', 'INSUFFICIENT_CREDITS'));
    end if;
  end if;

  insert into public.idempotency_keys (user_id, key, operation, status, generation_id)
    values (p_user_id, p_idempotency_key, 'reserve_credits', 'in_progress', p_generation_id);

  update public.subscriptions
    set credits_used = credits_used + p_amount,
        lifetime_credits_used = lifetime_credits_used + p_amount,
        updated_at = now()
    where user_id = p_user_id
      and status in ('active', 'trialing')
      and credits_used + p_amount <= credits_limit
    returning credits_limit - credits_used into v_balance_after;

  if not found then
    update public.idempotency_keys
      set status = 'failed',
          result = jsonb_build_object('success', false, 'code', 'INSUFFICIENT_CREDITS', 'error', 'You don''t have enough credits for this generation.'),
          updated_at = now()
      where user_id = p_user_id and key = p_idempotency_key and operation = 'reserve_credits';
    return jsonb_build_object('success', false, 'code', 'INSUFFICIENT_CREDITS', 'error', 'You don''t have enough credits for this generation.');
  end if;

  insert into public.credit_transactions (
    user_id, transaction_type, amount, balance_after, reference_type, reference_id,
    idempotency_key, description, metadata
  ) values (
    p_user_id, 'GENERATION_CHARGE', -p_amount, v_balance_after, 'generation', p_generation_id,
    p_idempotency_key, p_description, p_metadata
  ) returning id into v_tx_id;

  insert into public.usage_records (
    user_id, generation_id, project_id, generation_type, credits_consumed, status, provider, metadata
  ) values (
    p_user_id, p_generation_id, p_project_id, p_generation_type, p_amount, 'processing', p_provider, p_metadata
  )
  on conflict (generation_id) do update set
    credits_consumed = excluded.credits_consumed,
    status = 'processing',
    updated_at = now();

  update public.idempotency_keys
    set status = 'completed',
        result = jsonb_build_object('success', true, 'transactionId', v_tx_id, 'balanceAfter', v_balance_after),
        updated_at = now()
    where user_id = p_user_id and key = p_idempotency_key and operation = 'reserve_credits';

  return jsonb_build_object('success', true, 'transactionId', v_tx_id, 'balanceAfter', v_balance_after);
exception
  when unique_violation then
    return jsonb_build_object('success', false, 'code', 'DUPLICATE_REQUEST', 'error', 'This request is already being processed.');
end;
$$;

-- Marks a reserved generation's usage record as completed once the
-- provider call actually succeeds. Does not move credits - the charge
-- already happened in reserve_credits(). Idempotent by nature (a repeat
-- call just re-sets the same status).
create or replace function public.finalize_generation_charge(
  p_generation_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.usage_records
    set status = 'completed',
        metadata = metadata || p_metadata,
        updated_at = now()
    where generation_id = p_generation_id and status = 'processing';

  return jsonb_build_object('success', true);
end;
$$;

-- Atomically refunds a previously-reserved charge. Idempotent via its own
-- idempotency_keys entry (callers pass a key distinct from the charge's
-- own, e.g. 'refund:<generationId>'), and additionally guarded by only
-- updating a usage_records row that is still 'processing' or 'failed' -
-- an already-'refunded' row is never refunded twice even if called again
-- with a fresh key by mistake.
create or replace function public.refund_generation_credits(
  p_user_id uuid,
  p_amount integer,
  p_idempotency_key text,
  p_generation_id uuid,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing record;
  v_usage record;
  v_balance_after integer;
  v_tx_id uuid;
begin
  if p_amount <= 0 then
    return jsonb_build_object('success', false, 'code', 'INVALID_AMOUNT', 'error', 'Amount must be positive.');
  end if;

  select * into v_existing from public.idempotency_keys
    where user_id = p_user_id and key = p_idempotency_key and operation = 'refund_credits';
  if found then
    if v_existing.status = 'completed' then
      return v_existing.result;
    elsif v_existing.status = 'in_progress' then
      return jsonb_build_object('success', false, 'code', 'DUPLICATE_REQUEST', 'error', 'This refund is already being processed.');
    end if;
  end if;

  select * into v_usage from public.usage_records where generation_id = p_generation_id;
  if found and v_usage.status = 'refunded' then
    return jsonb_build_object('success', false, 'code', 'ALREADY_REFUNDED', 'error', 'This generation has already been refunded.');
  end if;

  insert into public.idempotency_keys (user_id, key, operation, status, generation_id)
    values (p_user_id, p_idempotency_key, 'refund_credits', 'in_progress', p_generation_id);

  update public.subscriptions
    set credits_used = greatest(credits_used - p_amount, 0),
        lifetime_credits_used = greatest(lifetime_credits_used - p_amount, 0),
        updated_at = now()
    where user_id = p_user_id
    returning credits_limit - credits_used into v_balance_after;

  if not found then
    update public.idempotency_keys
      set status = 'failed',
          result = jsonb_build_object('success', false, 'code', 'SUBSCRIPTION_NOT_FOUND'),
          updated_at = now()
      where user_id = p_user_id and key = p_idempotency_key and operation = 'refund_credits';
    return jsonb_build_object('success', false, 'code', 'SUBSCRIPTION_NOT_FOUND', 'error', 'No subscription found to refund into.');
  end if;

  insert into public.credit_transactions (
    user_id, transaction_type, amount, balance_after, reference_type, reference_id,
    idempotency_key, description, metadata
  ) values (
    p_user_id, 'REFUND', p_amount, v_balance_after, 'generation', p_generation_id,
    p_idempotency_key, p_description, p_metadata
  ) returning id into v_tx_id;

  update public.usage_records
    set status = 'refunded', metadata = metadata || p_metadata, updated_at = now()
    where generation_id = p_generation_id;

  update public.idempotency_keys
    set status = 'completed',
        result = jsonb_build_object('success', true, 'transactionId', v_tx_id, 'balanceAfter', v_balance_after),
        updated_at = now()
    where user_id = p_user_id and key = p_idempotency_key and operation = 'refund_credits';

  return jsonb_build_object('success', true, 'transactionId', v_tx_id, 'balanceAfter', v_balance_after);
exception
  when unique_violation then
    return jsonb_build_object('success', false, 'code', 'DUPLICATE_REQUEST', 'error', 'This refund is already being processed.');
end;
$$;

-- Marks a usage_records row as 'failed' without refunding - used when a
-- generation fails but the brief's "ambiguous state" rule applies (see
-- refund_generation_credits for the actual refund path). Kept separate so
-- an Edge Function can record "this failed" distinctly from "and here's
-- the refund", without forcing every failure to immediately refund.
create or replace function public.mark_generation_failed(p_generation_id uuid, p_metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.usage_records
    set status = 'failed', metadata = metadata || p_metadata, updated_at = now()
    where generation_id = p_generation_id and status = 'processing';
  return jsonb_build_object('success', true);
end;
$$;

-- Grants a subscription's monthly credit allowance, at most once per
-- billing period. Safe to call opportunistically/repeatedly (e.g. every
-- time the app opens) - it's a no-op until `current_period_end` has
-- actually passed, and idempotent per period via idempotency_keys.
create or replace function public.grant_monthly_credits(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub record;
  v_plan record;
  v_period_start timestamptz;
  v_key text;
  v_existing record;
  v_tx_id uuid;
begin
  select * into v_sub from public.subscriptions
    where user_id = p_user_id and status in ('active', 'trialing')
    order by created_at desc limit 1;
  if not found then
    return jsonb_build_object('success', false, 'code', 'NO_ACTIVE_SUBSCRIPTION', 'error', 'No active subscription found.');
  end if;

  if v_sub.current_period_end is not null and now() < v_sub.current_period_end then
    return jsonb_build_object('success', false, 'code', 'NOT_DUE_YET', 'nextGrantAt', v_sub.current_period_end);
  end if;

  select * into v_plan from public.plans where id = v_sub.plan_id and active = true;
  if not found then
    select * into v_plan from public.plans where code = v_sub.plan_name and active = true;
  end if;
  if not found then
    return jsonb_build_object('success', false, 'code', 'INVALID_PLAN', 'error', 'This subscription has no valid plan configured.');
  end if;

  v_period_start := coalesce(v_sub.current_period_start, date_trunc('month', now()));
  v_key := 'monthly:' || p_user_id::text || ':' || to_char(v_period_start, 'YYYY-MM-DD');

  select * into v_existing from public.idempotency_keys
    where user_id = p_user_id and key = v_key and operation = 'monthly_grant';
  if found then
    if v_existing.status = 'completed' then
      return v_existing.result;
    elsif v_existing.status = 'in_progress' then
      return jsonb_build_object('success', false, 'code', 'DUPLICATE_REQUEST', 'error', 'This grant is already being processed.');
    end if;
  end if;

  insert into public.idempotency_keys (user_id, key, operation, status)
    values (p_user_id, v_key, 'monthly_grant', 'in_progress');

  update public.subscriptions
    set credits_limit = v_plan.monthly_credits,
        credits_used = 0,
        lifetime_credits_earned = lifetime_credits_earned + v_plan.monthly_credits,
        current_period_start = now(),
        current_period_end = now() + interval '1 month',
        plan_id = v_plan.id,
        updated_at = now()
    where user_id = p_user_id;

  insert into public.credit_transactions (
    user_id, transaction_type, amount, balance_after, reference_type, reference_id,
    idempotency_key, description, metadata
  ) values (
    p_user_id, 'MONTHLY_GRANT', v_plan.monthly_credits, v_plan.monthly_credits, 'subscription', v_sub.id,
    v_key, 'Monthly credit grant (' || v_plan.name || ')', jsonb_build_object('period_start', v_period_start)
  ) returning id into v_tx_id;

  update public.idempotency_keys
    set status = 'completed',
        result = jsonb_build_object('success', true, 'granted', v_plan.monthly_credits, 'transactionId', v_tx_id),
        updated_at = now()
    where user_id = p_user_id and key = v_key and operation = 'monthly_grant';

  return jsonb_build_object('success', true, 'granted', v_plan.monthly_credits, 'transactionId', v_tx_id);
exception
  when unique_violation then
    return jsonb_build_object('success', false, 'code', 'DUPLICATE_REQUEST', 'error', 'This grant is already being processed.');
end;
$$;

-- Lock every billing function down to service-role only - a client must
-- never be able to call these directly via supabase.rpc(...) and bypass
-- an Edge Function's own auth/ownership/validation checks.
revoke execute on function public.reserve_credits(uuid, integer, text, uuid, text, uuid, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.finalize_generation_charge(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.refund_generation_credits(uuid, integer, text, uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function public.mark_generation_failed(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.grant_monthly_credits(uuid) from public, anon, authenticated;
-- get_credit_cost is read-only reference data - safe to leave callable by
-- authenticated users directly (mirrors the credit_costs table's own
-- public-read RLS policy above).

-- ---------------------------------------------------------------------------
-- handle_new_user(): now reads the Free plan's monthly_credits from
-- `plans` instead of a hard-coded literal, and populates the new
-- subscription columns - the actual grant amount for a brand-new user is
-- unchanged (still 50, since that's what the seeded 'free' plan row says).
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_free_plan record;
  v_sub_id uuid;
begin
  insert into public.profiles (user_id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');

  insert into public.user_settings (user_id)
  values (new.id);

  select * into v_free_plan from public.plans where code = 'free' and active = true limit 1;

  insert into public.subscriptions (
    user_id, plan_name, plan_id, status, credits_limit, credits_used,
    lifetime_credits_earned, current_period_start, current_period_end
  )
  values (
    new.id, 'free', v_free_plan.id, 'active',
    coalesce(v_free_plan.monthly_credits, 50), 0,
    coalesce(v_free_plan.monthly_credits, 50),
    now(), now() + interval '1 month'
  )
  returning id into v_sub_id;

  insert into public.credit_transactions (
    user_id, transaction_type, amount, balance_after, reference_type, reference_id, description, metadata
  ) values (
    new.id, 'SUBSCRIPTION_GRANT', coalesce(v_free_plan.monthly_credits, 50),
    coalesce(v_free_plan.monthly_credits, 50), 'subscription', v_sub_id,
    'Initial Free plan credits', '{}'::jsonb
  );

  insert into public.user_usage (user_id, period_start, period_end)
  values (
    new.id,
    date_trunc('month', now()),
    date_trunc('month', now()) + interval '1 month' - interval '1 second'
  );

  return new;
end;
$$;
