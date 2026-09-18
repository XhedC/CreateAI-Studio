# Database

Schema lives in [`supabase/migrations/`](../supabase/migrations/), applied in
filename order:

1. `20250101000000_extensions.sql` - `pgcrypto` (for `gen_random_uuid()`).
2. `20250101010000_tables.sql` - all 9 tables, indexes, check constraints.
3. `20250101020000_functions_triggers.sql` - `updated_at` triggers + the
   new-user bootstrap trigger.
4. `20250101030000_rls_policies.sql` - Row Level Security policies.
5. `20250101040000_storage.sql` - the private Storage bucket + its policies.
6. `20250101050000_security_hardening.sql` - pins `search_path` on the
   trigger function and revokes public/anon/authenticated `EXECUTE` on the
   `SECURITY DEFINER` bootstrap function (found by Supabase's security
   advisor after the first pass - see below).
7. `20250101060000_funnels.sql` (Phase 5) - the `funnels` and `funnel_leads`
   tables, their indexes, and their own RLS policies. See
   [funnel-generation.md](funnel-generation.md) for the schema they store.

Re-running `flutter build`/tests does not touch the database; these are plain
SQL files meant to be applied once per environment (see README "Supabase
setup").

## Tables

| Table | Purpose | Key columns |
|---|---|---|
| `profiles` | Display name/avatar for a user | `user_id` (unique, → `auth.users`), `full_name`, `avatar_url` |
| `projects` | A named container for related generations | `user_id`, `name`, `project_type` |
| `generations` | One AI generation request/result | `user_id`, `project_id` (nullable), `generation_type`, `prompt`, `status`, `provider`, `model`, `result_text`/`result_url`/`thumbnail_url`, `metadata` (jsonb) |
| `generation_files` | Files attached to or produced by a generation | `generation_id`, `user_id`, `storage_path`, `mime_type` |
| `user_usage` | Per-period generation counters | `user_id`, `period_start`/`period_end`, per-type counts |
| `credit_transactions` | Audit log of credit changes | `user_id`, `amount`, `transaction_type` |
| `subscriptions` | Current plan + credit balance | `user_id`, `plan_name`, `credits_limit`, `credits_used` |
| `user_settings` | Theme/language/notification prefs | `user_id` (unique), `theme_mode`, `language`, `notifications_enabled` |
| `notifications` | In-app notification feed | `user_id`, `title`, `message`, `is_read` |
| `funnels` (Phase 5) | The structured funnel document a `generation_type = 'funnel'` row produced | `user_id`, `project_id`, `generation_id` (unique, FK → `generations`, `on delete cascade`), `funnel_type`, `status`, `schema_version`, `content` (jsonb - the full `FunnelSchema`) |
| `funnel_leads` (Phase 5) | A visitor submission from a funnel's Lead Form | `funnel_id` (FK → `funnels`), `user_id` (the **funnel owner**, not the submitter), `name`/`email`/`phone`/`message` |

`generation_type` is constrained to `text/image/music/video/funnel` and
`status` to `pending/processing/completed/failed/cancelled` today. Adding a
6th creation type (voice, logo, ...) or a new status is one migration:
`alter table ... drop constraint ...` then re-add with the extended list -
`metadata` (jsonb) already absorbs any provider-specific detail without a
schema change.

Indexes exist on every column a screen filters or sorts by: `user_id` (all
tables), `project_id`/`generation_type`/`status`/`created_at` on
`generations`, `created_at` on `projects`/`notifications`/`credit_transactions`.

## Why `user_usage`, `credit_transactions`, and `subscriptions` are read-only from the client

Those three tables have **no INSERT/UPDATE RLS policy for authenticated
users** - only SELECT. Balances must only ever change through trusted backend
code (an Edge Function, or later a payment webhook), never a value the
Flutter app posts directly, otherwise a user could grant themselves credits.
Phase 1 seeds a free-plan row via the `handle_new_user` trigger; a future
phase adds the Edge Function(s) that debit/credit these tables.

## New-user bootstrap

`handle_new_user()` fires `after insert on auth.users` and creates one row
each in `profiles`, `user_settings`, `subscriptions` (free plan, 50 credits),
and `user_usage` (current month) - so the app never has to special-case "no
row yet" on first login. It runs `security definer` (required to write rows
owned by a different user id than the caller during signup) but its
`EXECUTE` grant is revoked from `anon`/`authenticated`/`public`, so it can
only ever run via the trigger, never be called directly through
PostgREST's auto-exposed RPC endpoint.

## Row Level Security

Every table has RLS enabled. The pattern is the same everywhere:

```sql
create policy "<table>_select_own" on public.<table>
  for select using (auth.uid() = user_id);
```

with matching `insert`/`update`/`delete` policies using
`with check (auth.uid() = user_id)` where the client is allowed to write.
No policy uses `using (true)` - there is no public-read requirement in
Phase 1. `generation_files`/`generations` join back to a project only via
`project_id`, so deleting a project (`on delete set null` on
`generations.project_id`) never orphans access - RLS is keyed on `user_id`
directly on every table, not inherited through a join.

`funnel_leads` (Phase 5) is the one table where `user_id` means the
*owner* of the related row (the funnel), not the person who created the
row (a visitor submitting the form has no account) - the policy shape is
identical (`auth.uid() = user_id`), it's just that "own" here means "leads
belonging to funnels you own." There is no public/anonymous insert policy
yet, since Phase 5 doesn't implement funnel publishing - see
[funnel-generation.md](funnel-generation.md).

## Storage

One private bucket, `app-storage`, holds every user file, namespaced as:

```
{user_id}/avatars/{file_name}
{user_id}/projects/{project_id}/{file_name}
{user_id}/generations/{generation_id}/{file_name}
{user_id}/uploads/{file_name}
```

(built by `lib/core/utils/storage_paths.dart`). `storage.objects` policies
check `auth.uid()::text = (storage.foldername(name))[1]` - the first path
segment must be the caller's own user id - for select/insert/update/delete,
so a user can only ever read or write inside their own folder. The bucket is
**not** public: `FileUploadService` reads files back via
`createSignedUrl(...)` (1 hour expiry), never `getPublicUrl()`. A production
follow-up should re-sign from the stored `storage_path` on demand instead of
caching a signed URL in `generation_files.file_url`/`projects.thumbnail_url`,
since signed URLs expire.

## Verifying RLS/security locally

Supabase's advisor is the fastest sanity check after any schema change:

```
mcp: get_advisors(project_id, type: "security")
```

(or, via the dashboard, Database → Advisors). This Phase 1 schema currently
reports zero security lints.
