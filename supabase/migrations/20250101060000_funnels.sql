-- CreateAI Studio - Phase 5
-- Funnel/landing-page generation. The structured funnel document (sections,
-- theme, seo, settings - see docs/funnel-generation.md) lives entirely in
-- `funnels.content` (JSONB); the flat columns alongside it are denormalized
-- for fast filtering/sorting (History, project detail) without parsing JSON.
--
-- `funnels.generation_id` links each funnel back to the `generations` row
-- that created it (Phase 1's History/Project architecture, reused
-- unchanged) with `on delete cascade` - deleting the generation (the
-- existing, already-tested delete path every other type already uses)
-- automatically removes its funnel row too, so no separate funnel-delete
-- Edge Function or RPC is needed.

-- ---------------------------------------------------------------------------
-- funnels
-- ---------------------------------------------------------------------------
create table if not exists public.funnels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  project_id uuid references public.projects (id) on delete set null,
  generation_id uuid not null unique references public.generations (id) on delete cascade,
  name text not null,
  description text,
  funnel_type text not null default 'custom'
    check (funnel_type in (
      'lead_generation', 'product_sales', 'service_business',
      'appointment_booking', 'event_registration', 'restaurant', 'pharmacy',
      'healthcare', 'real_estate', 'personal_brand', 'agency', 'ecommerce',
      'course', 'portfolio', 'custom'
    )),
  status text not null default 'draft' check (status in ('draft', 'archived')),
  schema_version integer not null default 1,
  content jsonb not null default '{}'::jsonb,
  thumbnail_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_funnels_user_id on public.funnels (user_id);
create index if not exists idx_funnels_project_id on public.funnels (project_id);
create index if not exists idx_funnels_generation_id on public.funnels (generation_id);
create index if not exists idx_funnels_funnel_type on public.funnels (funnel_type);
create index if not exists idx_funnels_created_at on public.funnels (created_at);

create trigger set_updated_at before update on public.funnels
  for each row execute function public.set_updated_at();

alter table public.funnels enable row level security;

create policy "funnels_select_own" on public.funnels
  for select using (auth.uid() = user_id);
create policy "funnels_insert_own" on public.funnels
  for insert with check (auth.uid() = user_id);
create policy "funnels_update_own" on public.funnels
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "funnels_delete_own" on public.funnels
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- funnel_leads
--
-- `user_id` here is the FUNNEL OWNER, not the visitor submitting the lead
-- (visitors have no account) - it exists purely so RLS can restrict reads to
-- "leads belonging to your own funnels" without a join, per the brief.
--
-- Phase 5 does not implement public publishing, so there is no anonymous
-- visitor pathway yet - insert is scoped to the owner's own authenticated
-- session (e.g. testing the Lead Form component against your own funnel).
-- A future "publish" phase introducing real, unauthenticated visitor
-- submissions must add that pathway through a dedicated, rate-limited Edge
-- Function (service-role insert after its own validation), never by
-- widening this table's RLS to `with check (true)`.
-- ---------------------------------------------------------------------------
create table if not exists public.funnel_leads (
  id uuid primary key default gen_random_uuid(),
  funnel_id uuid not null references public.funnels (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text,
  email text,
  phone text,
  message text,
  created_at timestamptz not null default now(),
  constraint funnel_leads_has_contact check (email is not null or phone is not null)
);

create index if not exists idx_funnel_leads_funnel_id on public.funnel_leads (funnel_id);
create index if not exists idx_funnel_leads_user_id on public.funnel_leads (user_id);
create index if not exists idx_funnel_leads_created_at on public.funnel_leads (created_at);

alter table public.funnel_leads enable row level security;

create policy "funnel_leads_select_own" on public.funnel_leads
  for select using (auth.uid() = user_id);
create policy "funnel_leads_insert_own" on public.funnel_leads
  for insert with check (auth.uid() = user_id);
create policy "funnel_leads_delete_own" on public.funnel_leads
  for delete using (auth.uid() = user_id);
