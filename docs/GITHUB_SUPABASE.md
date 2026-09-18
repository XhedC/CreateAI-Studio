# GitHub + Supabase workflow

This document is the operating manual for version control and backend
deployment for CreateAI Studio, written at the Phase 1-5 checkpoint. It
does not change anything about the app itself - it describes how the
project already is, and how every future phase should be committed and
deployed.

## 1. GitHub repository structure

The repository root **is** the Flutter project root:

```
lib/                 # Flutter/Dart application source
test/                # flutter test suite
android/              # Android platform project (no iOS yet - see README)
supabase/
  migrations/          # SQL, applied in filename-timestamp order - see §5
  functions/           # One folder per Edge Function - see §6
docs/                 # Architecture + one deep-dive doc per generation type
env/
  dev.json.example      # Tracked template - safe, no real values
  dev.json               # Gitignored - real Supabase URL/anon key, local only
.env.example           # Root-level variable-name reference (this checkpoint) - see §9
.gitignore
pubspec.yaml / pubspec.lock
README.md
```

Nothing under `build/`, `.dart_tool/`, `.idea/`, or `android/local.properties`
belongs in the repository - see §10 (`.gitignore`).

## 2. Branch strategy

A single long-lived branch, **`main`**, holds every completed, checkpointed
phase. This project is built by one contributor working directly with an
AI pair-programmer through sequential, fully-tested phases (not a team of
parallel contributors), so a heavier branch model (`develop`, per-feature
branches, etc.) is deliberately not imposed - it would add process
overhead with no corresponding benefit at this stage.

- **`main`** - always in a working, tested, checkpointed state. Every
  commit on `main` should pass `flutter analyze` and `flutter test`.
- **Phase tags** (`phase-1-complete`, ..., `phase-5-complete`, ...) mark
  the exact commit where a phase was checkpointed - see §3 and §12. Tags,
  not branches, are what "Phase N is done" refers back to.
- If work ever needs to happen in parallel with an in-progress phase (e.g.
  an urgent fix while Phase 6 is mid-flight), branch from the last phase
  tag as `hotfix/<short-description>` and merge back to `main` when done.
  This hasn't been needed through Phase 5.

## 3. Commit strategy

- Commit at meaningful checkpoints - a completed phase, a completed
  sub-feature within a phase, or a fix - not on every individual file
  edit. Within a phase's development, intermediate commits are fine and
  encouraged for anything substantial enough to want a rollback point.
- **One phase = one checkpoint commit at minimum**, using the exact
  message format the phase brief specifies (e.g. this checkpoint's
  `"Phase 1-5 Complete - GitHub Supabase Checkpoint"`). If a phase's work
  was split into several commits, the final checkpoint commit is what gets
  tagged.
- Commit messages describe *why*, not just *what* - see the repository's
  own commit history once it exists for the established tone (this
  project's own summaries, e.g. in the phase completion reports, are a
  good source for the "why").
- Never commit: anything matched by `.gitignore` (see §10), a real
  `env/*.json`, a real API key or password anywhere, or generated build
  output.
- Review `git status`/`git diff --stat` before every commit - especially
  after a broad `git add` - to make sure nothing unexpected (a stray local
  config, a debug file, a secret) is staged.

## 4. Supabase migration workflow

Every schema change is a new, timestamped SQL file under
`supabase/migrations/`, applied **once**, in filename order, and never
edited after it has been applied to any environment (a mistake gets fixed
by a new migration, not by rewriting history):

```
supabase/migrations/
  20250101000000_extensions.sql        # pgcrypto
  20250101010000_tables.sql             # Phase 1 core schema
  20250101020000_functions_triggers.sql # updated_at triggers, new-user bootstrap
  20250101030000_rls_policies.sql       # Phase 1 RLS
  20250101040000_storage.sql            # app-storage bucket + policies
  20250101050000_security_hardening.sql # advisor-driven fixes
  20250101060000_funnels.sql            # Phase 5: funnels + funnel_leads
```

**To apply migrations to a project** (a fresh project, or one that's
fallen behind):
```bash
supabase link --project-ref <your-project-ref>
supabase db push
```
This project's own Supabase project already has every migration through
`20250101060000_funnels.sql` applied - `supabase db push` against it again
is a safe no-op (Supabase tracks which migrations have already run).

**Adding a new migration** (every future phase that touches the schema):
1. Write a new file, timestamped **after** every existing one, named
   `<timestamp>_<short_description>.sql`.
2. Never modify an already-applied migration file - not even to fix a
   typo. Add a new migration that corrects it instead.
3. Prefer additive, non-destructive DDL (`create table if not exists`,
   `alter table ... add column ...`, new indexes/policies). A genuinely
   destructive change (dropping a column, narrowing a constraint on
   existing data) needs an explicit, separate confirmation from whoever's
   driving the phase before it's applied to a project with real data -
   never apply one silently as part of routine feature work.
4. Apply it with `supabase db push` (or, in an AI-assisted session, the
   Supabase MCP `apply_migration` tool) and re-run the security/performance
   advisors afterward - every prior phase in this project ended with 0
   security lints; keep that streak.

## 5. Supabase database structure (as of Phase 5)

See [database.md](database.md) for the full column-by-column reference.
Summary: 11 tables, all with RLS enabled, all keyed by `user_id` directly
(never inherited through a join) -

| Table | Added | Purpose |
|---|---|---|
| `profiles`, `user_settings`, `subscriptions`, `user_usage`, `notifications` | Phase 1 | account/session scaffolding |
| `projects` | Phase 1 | groups related generations |
| `generations`, `generation_files` | Phase 1 | one row per AI request; extra output files |
| `credit_transactions` | Phase 1 | audit log; read-only from the client |
| `funnels`, `funnel_leads` | Phase 5 | structured funnel documents + lead capture |

`generations.generation_type` (`text/image/music/video/funnel`) and
`.status` (`pending/processing/completed/failed/cancelled`) are enforced
by CHECK constraints - extending either is a one-line
`alter table ... drop constraint ... / add constraint ...` migration, not
a redesign. `funnels.generation_id` has `on delete cascade` from
`generations` - deleting a generation is the only "delete a funnel"
operation that exists, by design (see
[funnel-generation.md](funnel-generation.md)).

`user_usage`, `credit_transactions`, and `subscriptions` intentionally have
**no INSERT/UPDATE policy for authenticated users** - only SELECT. Balances
change exclusively through trusted backend code (an Edge Function's
service-role client). Never add a client-writable policy to these three
tables to "make something easier" - that reopens the exact hole this
design closes.

## 6. Edge Functions

```
supabase/functions/
  generate-image/    # Phase 2 - synchronous
  generate-music/    # Phase 3 - synchronous
  generate-video/    # Phase 4 - async: creates a job, returns immediately
  video-status/      # Phase 4 - polled by the client to resolve the job
  generate-funnel/   # Phase 5 - synchronous; the only one that writes to a
                      #  table other than subscriptions/credit_transactions
                      #  (it writes to `funnels`, never to `generations`)
```

Every function shares the same security shape - see each type's own doc
(`image-generation.md`, `music-generation.md`, `video-generation.md`,
`funnel-generation.md`) for the full walkthrough:
1. Identity comes **only** from the verified JWT
   (`userClient.auth.getUser()`) - never from the request body.
2. A user-scoped client (anon key + forwarded `Authorization` header) is
   used for anything that must respect RLS (Storage, `generations` reads,
   `funnels` writes).
3. A service-role client is used **only** for `subscriptions` /
   `credit_transactions` - the two tables with no client-write policy.
4. No Edge Function writes to `generations` itself (Phase 1's
   `GenerationRepository`/`GenerationOrchestrator`, already tested, is the
   single writer) - `generate-funnel` writing to `funnels` is the one
   exception, and it's a different table, not `generations`.
5. Every provider vendor key lives **only** as an Edge Function secret
   (`supabase secrets set NAME=value`), resolved by a `resolveProvider()`
   function that defaults to a safe mock and fails loudly (never silently
   falls back to mock) if a real provider is requested without its key.

**Deploying/redeploying a function:**
```bash
supabase functions deploy <function-name>
```
All five are already deployed to this project with `verify_jwt: true`
(confirmed live: every one returns `401` to a request with no
`Authorization` header).

## 7. Storage

One private bucket, `app-storage` (`public: false`). Every object path is
namespaced `{user_id}/...`, and all four storage policies
(select/insert/update/delete) require
`auth.uid()::text = (storage.foldername(name))[1]` - the first path
segment must be the caller's own id. The app never calls
`getPublicUrl()`; every read goes through a short-lived (1 hour)
`createSignedUrl()`. See [database.md](database.md) §Storage for the full
path layout.

## 8. Row Level Security

Confirmed at this checkpoint (queried live via `pg_policies`): every
`public` schema table's policies are exactly `auth.uid() = user_id` (or
the matching `with_check`), with no `using (true)` anywhere. A user cannot
read, modify, or delete another user's profile, project, generation,
funnel, funnel lead, or Storage object - RLS is keyed directly on
`user_id`/the storage path's first segment on every table, not inherited
through a join that a bug could bypass. See §5 for why
`subscriptions`/`user_usage`/`credit_transactions` deliberately have no
client-write policy.

**Never weaken RLS to make a feature easier to build.** If a future phase
seems to need a public/anonymous read or write policy (e.g. a future
"publish this funnel publicly" feature), that pathway belongs behind a
dedicated, rate-limited Edge Function using the service role - see
[funnel-generation.md](funnel-generation.md)'s note on this for the
concrete example already anticipated in Phase 5.

## 9. Environment variables

Two layers, never mixed:

- **Flutter client** (`env/dev.json`, gitignored; `env/dev.json.example`,
  tracked): `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `PRODUCTION`. The anon key
  is not a secret by Supabase's own design (it's meant to ship inside
  client apps) - access control is RLS, not hiding this value. Even so, it
  is gitignored here as routine hygiene and to keep per-environment values
  out of history.
- **Supabase Edge Function secrets** (`supabase secrets set NAME=value`,
  never in git, never in the Flutter app): every `*_PROVIDER`/`*_MODEL`/
  `*_API_KEY` triple for image/music/video/funnel generation, plus the
  platform-injected `SUPABASE_URL`/`SUPABASE_ANON_KEY`/
  `SUPABASE_SERVICE_ROLE_KEY` every function receives automatically.

`.env.example` (repo root) lists every variable name used anywhere in the
project - client and backend - so anyone auditing or onboarding has one
place to see the full surface, without ever containing a real value. Verified at this checkpoint: grepping `lib/` for every provider secret name
and for `String.fromEnvironment` turns up exactly two client-side
variables (`supabaseUrl`, `supabaseAnonKey`) and nothing else - no AI
provider key of any kind is reachable from the Flutter app.

## 10. Secret management / `.gitignore`

What must never be committed, and where it's excluded:

| Secret type | Where it lives | Gitignore coverage |
|---|---|---|
| Supabase anon key | `env/dev.json` | `/env/*.json` (all real config files) |
| Supabase service role key | Edge Function runtime env only (platform-injected) | never written to any file in this repo |
| AI provider API keys | Edge Function secrets (`supabase secrets set`) | never written to any file in this repo |
| Android release keystore | not created yet (release signs with the debug keystore) | `*.jks`, `*.keystore`, `*.p12`, `/android/key.properties` |
| Local SDK paths | `android/local.properties` | `/android/local.properties` |
| Generic `.env` files | not used by this project (it uses `env/*.json`) | `.env`, `.env.*` (kept: `.env.example`) |

If a real secret is ever found staged for commit, the fix is to unstage
it, rotate the credential if it was ever pushed (not just committed
locally), and add/confirm a `.gitignore` rule so it can't happen again -
never just delete the file and re-commit, since the secret would still be
readable from git history.

## 11. Development workflow

For a single change or feature within a phase:

1. Make the change.
2. `flutter analyze` - must be clean.
3. `flutter test` - must pass, including every prior phase's tests.
4. If the change touched Supabase (schema, RLS, Edge Function), re-check
   the security advisor (`get_advisors(type: "security")` via MCP, or the
   Supabase dashboard) - it should stay at 0 lints.
5. `git add` the specific files that changed (never a blanket `git add -A`
   without reviewing `git status` first), commit with a message describing
   why, push to `main` (or a hotfix branch - see §2) once the person
   driving the session is ready.

## 12. Production deployment / phase-checkpoint workflow

**Every future phase follows this exact sequence, in order:**

```
Development
  → Testing            (flutter analyze + flutter test, and flutter build
                         apk --debug for a real compile check)
  → Security check      (grep for secrets; re-run the Supabase security
                         advisor; confirm RLS wasn't weakened)
  → Git commit          (see §3 for message conventions)
  → GitHub push          (only once explicitly confirmed - never push
                          automatically as part of finishing a phase)
  → Phase checkpoint     (tag the commit, e.g. `phase-6-complete`, once
                          pushed)
```

Nothing in this sequence is optional, and the order matters: a phase is
not "done" until it's tested and security-checked, and it is not
"checkpointed" until it's both committed *and* tagged. Pushing to GitHub
is always a separate, explicitly-confirmed action - a completed local
commit is not implicit permission to push.

**Deploying the backend** for a phase that touched Supabase: apply new
migrations (`supabase db push`) and/or redeploy changed functions
(`supabase functions deploy <name>`) against the target project *before*
distributing a client build that depends on them - this project's single
shared dev project doubles as "production" today, so in practice this
means: apply/deploy first, then build/test the app against it.

**Building a distributable client:**
```bash
flutter build apk --release --dart-define-from-file=env/dev.json
```
The release build currently signs with the debug keystore (see the `TODO`
in `android/app/build.gradle.kts`) - replace it with a real signing config
(and update §10's gitignore expectations to match the real keystore
filename) before any Play Store upload.
