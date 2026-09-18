-- CreateAI Studio - Phase 1
-- Core schema. UUID primary keys, explicit foreign keys to auth.users,
-- created_at/updated_at timestamps, and indexes on the columns every screen
-- filters or sorts by (user_id, project_id, generation_type, status,
-- created_at).
--
-- NOTE on the CHECK constraints below: they encode the enum values Phase 1
-- ships with. Adding a new creation type (e.g. "voice", "logo") or a new
-- plan later is a one-line migration: `alter table ... drop constraint ...`
-- then re-add with the extended list. metadata/JSONB columns absorb
-- provider-specific detail without ever needing a migration.

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_profiles_user_id on public.profiles (user_id);

-- ---------------------------------------------------------------------------
-- projects
-- ---------------------------------------------------------------------------
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  description text,
  project_type text not null default 'general'
    check (project_type in ('general', 'image', 'music', 'video', 'funnel', 'content')),
  thumbnail_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_projects_user_id on public.projects (user_id);
create index if not exists idx_projects_created_at on public.projects (created_at);

-- ---------------------------------------------------------------------------
-- generations
-- ---------------------------------------------------------------------------
create table if not exists public.generations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  project_id uuid references public.projects (id) on delete set null,
  generation_type text not null
    check (generation_type in ('text', 'image', 'music', 'video', 'funnel')),
  prompt text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  provider text,
  model text,
  result_text text,
  result_url text,
  thumbnail_url text,
  metadata jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists idx_generations_user_id on public.generations (user_id);
create index if not exists idx_generations_project_id on public.generations (project_id);
create index if not exists idx_generations_generation_type on public.generations (generation_type);
create index if not exists idx_generations_status on public.generations (status);
create index if not exists idx_generations_created_at on public.generations (created_at);

-- ---------------------------------------------------------------------------
-- generation_files
-- ---------------------------------------------------------------------------
create table if not exists public.generation_files (
  id uuid primary key default gen_random_uuid(),
  generation_id uuid not null references public.generations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  file_name text not null,
  file_type text not null,
  mime_type text not null,
  storage_path text not null,
  file_url text,
  file_size bigint,
  created_at timestamptz not null default now()
);

create index if not exists idx_generation_files_generation_id
  on public.generation_files (generation_id);
create index if not exists idx_generation_files_user_id on public.generation_files (user_id);

-- ---------------------------------------------------------------------------
-- user_usage
-- ---------------------------------------------------------------------------
create table if not exists public.user_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  period_start timestamptz not null,
  period_end timestamptz not null,
  images_generated integer not null default 0,
  videos_generated integer not null default 0,
  music_generated integer not null default 0,
  text_generations integer not null default 0,
  funnel_generations integer not null default 0,
  total_credits_used integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, period_start)
);

create index if not exists idx_user_usage_user_id on public.user_usage (user_id);

-- ---------------------------------------------------------------------------
-- credit_transactions
-- ---------------------------------------------------------------------------
create table if not exists public.credit_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount integer not null,
  transaction_type text not null
    check (transaction_type in ('purchase', 'generation', 'bonus', 'refund', 'subscription')),
  description text,
  reference_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_credit_transactions_user_id on public.credit_transactions (user_id);
create index if not exists idx_credit_transactions_created_at
  on public.credit_transactions (created_at);

-- ---------------------------------------------------------------------------
-- subscriptions
-- ---------------------------------------------------------------------------
create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_name text not null default 'free' check (plan_name in ('free', 'pro', 'business')),
  status text not null default 'active' check (status in ('active', 'cancelled', 'expired', 'past_due')),
  credits_limit integer not null default 50,
  credits_used integer not null default 0,
  started_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_subscriptions_user_id on public.subscriptions (user_id);

-- ---------------------------------------------------------------------------
-- user_settings
-- ---------------------------------------------------------------------------
create table if not exists public.user_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  theme_mode text not null default 'system' check (theme_mode in ('system', 'light', 'dark')),
  language text not null default 'en',
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_settings_user_id on public.user_settings (user_id);

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  message text not null,
  notification_type text not null default 'system',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user_id on public.notifications (user_id);
create index if not exists idx_notifications_created_at on public.notifications (created_at);
