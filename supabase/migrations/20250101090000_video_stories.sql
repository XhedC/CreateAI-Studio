-- Video Stories & Segments tables for the AI Video Maker feature.
-- Supports multi-segment video stories with continue-editing workflow.

create table if not exists public.video_stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid references public.projects(id) on delete set null,
  title text not null default 'Untitled Story',
  aspect_ratio text not null default '16:9',
  quality text not null default '720p',
  style text not null default 'cinematic',
  fps integer not null default 24,
  status text not null default 'draft'
    check (status in ('draft', 'processing', 'completed', 'exported')),
  final_video_url text,
  thumbnail_url text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create index idx_video_stories_user_id on public.video_stories(user_id);
create index idx_video_stories_status on public.video_stories(status);

create table if not exists public.video_segments (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.video_stories(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  order_index integer not null default 0,
  input_type text not null default 'text'
    check (input_type in ('text', 'photo', 'voice')),
  prompt text not null default '',
  photo_url text,
  voice_url text,
  duration_seconds integer not null default 10
    check (duration_seconds between 5 and 60),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  video_url text,
  thumbnail_url text,
  generation_id uuid references public.generations(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index idx_video_segments_story_id on public.video_segments(story_id);
create index idx_video_segments_status on public.video_segments(status);

-- updated_at trigger for video_stories
create or replace function public.set_video_story_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_video_stories_updated_at
  before update on public.video_stories
  for each row execute function public.set_video_story_updated_at();

-- RLS policies

alter table public.video_stories enable row level security;
alter table public.video_segments enable row level security;

-- video_stories: users can only access their own stories
create policy "Users can view own stories"
  on public.video_stories for select
  using (auth.uid() = user_id);

create policy "Users can create own stories"
  on public.video_stories for insert
  with check (auth.uid() = user_id);

create policy "Users can update own stories"
  on public.video_stories for update
  using (auth.uid() = user_id);

create policy "Users can delete own stories"
  on public.video_stories for delete
  using (auth.uid() = user_id);

-- video_segments: users can only access segments of their own stories
create policy "Users can view own segments"
  on public.video_segments for select
  using (auth.uid() = user_id);

create policy "Users can create own segments"
  on public.video_segments for insert
  with check (auth.uid() = user_id);

create policy "Users can update own segments"
  on public.video_segments for update
  using (auth.uid() = user_id);

create policy "Users can delete own segments"
  on public.video_segments for delete
  using (auth.uid() = user_id);
