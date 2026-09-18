-- CreateAI Studio - Phase 7
-- Publishing, export & sharing foundation for funnels/landing pages.
--
-- Extends (never replaces) Phase 5's `funnels` table with an orthogonal
-- publishing lifecycle - `status` (draft/archived) is untouched and keeps
-- its existing meaning; `published`/`published_at`/`unpublished_at` track
-- whether a funnel currently has a live public page, independent of that.
--
-- Design decisions (see docs/PHASE_7_PUBLISHING.md for the full writeup):
--  - `published_content` is a SNAPSHOT of `content` taken at publish time,
--    not a live mirror. A user can keep editing the draft after publishing
--    without changing what visitors see until they explicitly republish -
--    this is the entire reason a separate column exists rather than
--    visitors reading `content` directly.
--  - `public_slug` is generated once (by the `publish-funnel` Edge
--    Function) and never changes afterward, even across unpublish/
--    republish cycles, so a previously-shared link keeps working.
--  - The `funnels` table itself is NOT made publicly readable (no `to
--    anon` policy is added here) - a public visitor has no session at
--    all, and Postgres RLS is row-level, not column-level, so any
--    policy exposing published rows would still let a client `select *`
--    and read the DRAFT `content` column too. Public reads instead go
--    through a SECURITY DEFINER RPC (`get_public_funnel`, below) that
--    explicitly allowlists which columns are ever returned.
--  - Public lead submission similarly does not touch `funnel_leads`'
--    RLS (still zero anonymous-insert policy, exactly as the Phase 5
--    migration's own comments anticipated) - it goes through a second
--    SECURITY DEFINER RPC (`submit_funnel_lead`) that validates the
--    funnel is actually published before inserting anything.
--
-- Safe to run: purely additive (new nullable/defaulted columns, new
-- indexes, two new functions) against the existing `funnels`/
-- `funnel_leads` tables - no existing column, constraint, or row is
-- changed or removed.

-- ---------------------------------------------------------------------------
-- funnels - publishing columns
-- ---------------------------------------------------------------------------
alter table public.funnels
  add column if not exists published boolean not null default false,
  add column if not exists published_at timestamptz,
  add column if not exists unpublished_at timestamptz,
  add column if not exists public_slug text,
  add column if not exists published_content jsonb,
  add column if not exists published_version integer not null default 0;

-- A slug is only ever compared against other slugs once assigned; the
-- partial unique index keeps every never-published funnel's `null` slug
-- from colliding with itself (a plain unique constraint would otherwise
-- treat multiple NULLs as fine anyway under Postgres semantics, but being
-- explicit here documents the intent).
create unique index if not exists idx_funnels_public_slug
  on public.funnels (public_slug) where public_slug is not null;

-- Used by get_public_funnel()'s lookup and by the owner dashboard's
-- "published funnels" filtering.
create index if not exists idx_funnels_published
  on public.funnels (published) where published = true;

-- ---------------------------------------------------------------------------
-- get_public_funnel(slug) - the ONLY way a public visitor's client (using
-- just the anon/publishable key, no session) can read funnel data.
-- SECURITY DEFINER so it can see the row regardless of RLS, but it never
-- returns the row itself - only an explicit, hand-picked allowlist of
-- fields, and only for a row that is currently published. Never returns
-- `id`, `user_id`, `project_id`, `generation_id`, `status`, the draft
-- `content`, or any other internal/owner metadata.
-- ---------------------------------------------------------------------------
create or replace function public.get_public_funnel(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'name', f.name,
    'funnelType', f.funnel_type,
    'content', f.published_content,
    'publicSlug', f.public_slug,
    'publishedAt', f.published_at,
    'publishedVersion', f.published_version
  )
  from public.funnels f
  where f.public_slug = p_slug
    and f.published = true;
$$;

-- Callable by anyone, including a truly anonymous visitor - this is the
-- deliberate public entry point. It does no harm to leave it callable by
-- `authenticated` too (an owner previewing their own published page uses
-- the exact same function).
grant execute on function public.get_public_funnel(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- submit_funnel_lead(...) - the ONLY way a public visitor's client can
-- create a `funnel_leads` row. SECURITY DEFINER so it can insert despite
-- `funnel_leads` having zero anonymous-insert RLS policy (deliberately -
-- see the Phase 5 migration's own comments). Validates the funnel exists
-- and is currently published before writing anything, validates the
-- submitted fields server-side (never trusts a client-side check alone),
-- and applies a minimal duplicate-submission guard.
-- ---------------------------------------------------------------------------
create or replace function public.submit_funnel_lead(
  p_slug text,
  p_name text default null,
  p_email text default null,
  p_phone text default null,
  p_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funnel record;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_email text := nullif(trim(coalesce(p_email, '')), '');
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_message text := nullif(trim(coalesce(p_message, '')), '');
  v_recent_count integer;
begin
  if v_email is null and v_phone is null then
    return jsonb_build_object(
      'success', false, 'code', 'MISSING_CONTACT',
      'error', 'Please provide an email address or phone number.'
    );
  end if;

  if v_email is not null then
    if length(v_email) > 320 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      return jsonb_build_object(
        'success', false, 'code', 'INVALID_EMAIL',
        'error', 'Please enter a valid email address.'
      );
    end if;
  end if;

  if v_name is not null and length(v_name) > 200 then
    return jsonb_build_object('success', false, 'code', 'INVALID_INPUT', 'error', 'Name is too long.');
  end if;
  if v_phone is not null and length(v_phone) > 40 then
    return jsonb_build_object('success', false, 'code', 'INVALID_INPUT', 'error', 'Phone number is too long.');
  end if;
  if v_message is not null and length(v_message) > 4000 then
    return jsonb_build_object('success', false, 'code', 'INVALID_INPUT', 'error', 'Message is too long.');
  end if;

  select id, user_id into v_funnel from public.funnels
    where public_slug = p_slug and published = true;

  if not found then
    return jsonb_build_object(
      'success', false, 'code', 'NOT_FOUND',
      'error', 'This page is no longer available.'
    );
  end if;

  -- Basic abuse guard: the same email submitting to the same funnel more
  -- than once in a short window is almost always a duplicate/double-tap,
  -- not a second genuine lead. Not a general rate limiter (see
  -- docs/PHASE_7_PUBLISHING.md "future improvements") - just enough to
  -- stop the loading-state double-submit class of bug from row-doubling.
  if v_email is not null then
    select count(*) into v_recent_count from public.funnel_leads
      where funnel_id = v_funnel.id
        and email = v_email
        and created_at > now() - interval '60 seconds';
    if v_recent_count > 0 then
      -- Treat as success from the visitor's point of view - they already
      -- submitted; a second identical tap should not show an error.
      return jsonb_build_object('success', true, 'duplicate', true);
    end if;
  end if;

  insert into public.funnel_leads (funnel_id, user_id, name, email, phone, message)
  values (v_funnel.id, v_funnel.user_id, v_name, v_email, v_phone, v_message);

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.submit_funnel_lead(text, text, text, text, text) to anon, authenticated;
