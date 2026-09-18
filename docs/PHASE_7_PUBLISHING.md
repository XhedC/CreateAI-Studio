# Phase 7 — Publishing, Export & Sharing

This document describes the publishing/export/sharing foundation for
funnels built in Phase 7: a funnel moves from draft → published (with a
stable public URL) → optionally unpublished/republished, visitors can view
a published funnel and submit its lead form without signing in, and the
owner can export the funnel's JSON configuration. **No real custom-domain
billing, payment functionality, or CAPTCHA/anti-bot system was built** -
all explicitly out of scope for this phase.

## Reuse-first: what Phase 7 extends rather than replaces

Phase 5 already had everything a funnel *is* - schema, validator, editor,
renderer, lead capture. Phase 7 only adds the *publishing lifecycle* on
top: new columns on the existing `funnels` table, two new SQL functions,
one new Edge Function, and new screens/widgets that reuse `FunnelRenderer`
and the existing lead-form pattern rather than duplicating them. Nothing
in Phase 1-6 was redesigned.

## Publishing architecture

### Schema changes (`supabase/migrations/20250101080000_funnel_publishing.sql`)

Added to `funnels` (all nullable/defaulted - purely additive):

| Column | Purpose |
|---|---|
| `published boolean` | Whether the funnel currently has a live public page. Orthogonal to the existing `status` (draft/archived) column - untouched. |
| `published_at` / `unpublished_at timestamptz` | When the funnel was last published / unpublished. |
| `public_slug text` | Stable, unique, human-readable public identifier. Generated once, never regenerated. |
| `published_content jsonb` | A **snapshot** of `content` taken at publish time - see "Published snapshot" below. |
| `published_version integer` | Incremented on every successful publish/republish. |

Indexes: a partial unique index on `public_slug` (where not null), and a
partial index on `published` (where true) for the lookup/listing paths.

### Why a snapshot, not a live mirror

If visitors read `content` directly, every keystroke in the editor would
instantly change what's public. Instead, `publish-funnel` copies
`content` into `published_content` only when the owner explicitly
publishes or republishes. `FunnelModel.hasUnpublishedChanges` (a getter
comparing `updated_at` against `published_at`) is what powers the editor's
"you have unsaved changes since this was last published" notice - no
extra column needed, since any further draft edit already bumps
`updated_at` via the existing `set_updated_at` trigger.

### Publishing lifecycle

```
Draft (published=false, public_slug=null)
  --publish-->
Published (published=true, public_slug='my-funnel', published_version=1)
  --edit draft (content changes, published_content untouched)-->
Published, but hasUnpublishedChanges=true
  --republish-->
Published, published_version=2, published_content refreshed, SAME public_slug
  --unpublish-->
Unpublished (published=false, public_slug='my-funnel' UNCHANGED, published_content UNCHANGED)
  --publish again-->
Published, published_version=3, SAME public_slug (URL keeps working)
```

`public_slug` is only ever assigned once (on first successful publish) and
is deliberately never regenerated - unpublishing does not clear it, and
republishing reuses it. This is the entire "publish versioning" model the
brief asked for: no Git-style history, just "the live snapshot" plus a
monotonically increasing version counter.

## Public funnel slug

Generated server-side in `publish-funnel` (`slugify()`): lowercase,
accent-stripped, non-alphanumeric runs collapsed to a single `-`, trimmed,
capped at 60 characters, falling back to `"funnel"` if the name has no
usable characters. On first publish, if the base slug is already taken
(by a **different** funnel - possibly a different user entirely), the
function retries with `-2`, `-3`, ... up to 8 attempts, relying on the
real Postgres unique index (`idx_funnels_public_slug`) as the actual
source of truth - a `23505` unique-violation error is what triggers the
next attempt, not a separate (and inherently racy) existence check. A
user's own RLS-scoped client cannot even see other users' funnel rows to
check for collisions directly, which is exactly why this "attempt the
real update, retry on conflict" approach was chosen over a
select-then-insert pattern.

## Publish button / owner publishing dashboard

`PublishStatusCard` (`lib/features/funnel_generation/presentation/widgets/publish_status_card.dart`),
embedded in the Funnel Editor, shows:
- A status badge (Draft / Published / Unpublished) and the last published
  timestamp.
- The public URL (once one exists) with Copy Link / Share actions.
- A "Preview Published Version" button (see below).
- Publish (with a confirmation dialog naming the funnel and its URL) /
  Republish + Unpublish (with its own confirmation) as appropriate to the
  current state.
- A post-publish success dialog with Copy Link / Share / View Published
  Funnel actions.

`GenerationDetailScreen`'s existing funnel summary card also gained a
small Draft/Published/Unpublished badge, so publishing status is visible
from the generation history view too, not only inside the editor.

## Public funnel view

`PublicFunnelViewScreen` (`lib/features/funnel_generation/presentation/screens/public_funnel_view_screen.dart`)
is the **only** place in the app that renders `FunnelRenderer` with
`publicSlug` set (as opposed to `funnelId`, the owner-preview path).
It requires no authentication, loads via `publicFunnelProvider(slug)`,
and handles three distinct states:
- **Loading** - a spinner.
- **Not found** - `AsyncData(null)`: covers a draft, an unpublished
  funnel, and a genuinely nonexistent slug identically (see "Public data
  access" below for why that's deliberate), shown as "Funnel not found."
- **Error** - `AsyncError`: a genuine network/server failure, shown
  separately with a retry action, never a raw database error message.

It reuses `FunnelRenderer` completely, so every section type (hero,
benefits/features/services/products, pricing, testimonials, statistics,
about/contact, FAQ, lead form, appointment/final CTA, footer) renders
identically to the owner's own preview - there is no separate,
possibly-diverging "public" rendering path to maintain.

When a signed-in user (almost certainly the owner, previewing) opens this
screen, a small "PUBLIC PUBLISHED VERSION" banner is shown to distinguish
it from the editor's own live-draft preview; a real anonymous visitor
never sees this banner, since real visitors are never signed in.

## Public routing

The app is Android-only (no Flutter web was added - explicitly out of
scope per the brief). `/f/:slug` is a real `GoRouter` route, reachable
**without** authentication via one narrow, explicitly-commented exception
in `app_router.dart`'s `redirect` callback:

```dart
final isPublicFunnelRoute = location.startsWith('${RoutePaths.publicFunnelPrefix}/');
if (isPublicFunnelRoute) return null;
```

This is the only change made to the Splash/Auth flow in this phase, and
it does not touch the router-refresh-race fix that resolved the
previously-reported Splash hang (see "Known limitations" below for that
fix's current status).

**What this does and does not achieve today:** inside this Android app,
`/f/:slug` is fully functional (reachable, renders, submits leads) for
in-app previewing/testing. It does **not** make published funnels
reachable from an actual web browser, since nothing in this repository
serves a web page - there is no Flutter web build, no static host, no
server. A real "share this link and anyone can open it in Chrome"
experience requires a **separate public web deployment** (see "Future
production architecture" below) that calls the exact same
`get_public_funnel`/`submit_funnel_lead` RPCs this phase built. The
backend half of that future deployment already exists and is already
tested; only the web frontend does not exist yet.

## Public data access

The `funnels` table itself was **not** made publicly readable - no `to
anon` RLS policy was added. Postgres RLS is row-level, not column-level:
a policy that exposes published *rows* would still let any client
`select *` and read the **draft** `content` column, the owner's
`user_id`, `project_id`, `generation_id`, and `status` too. Instead:

- **`get_public_funnel(p_slug text) returns jsonb`** - a `SECURITY
  DEFINER` SQL function, granted to `anon` and `authenticated`. It
  queries `funnels where public_slug = $1 and published = true` and
  returns a **hand-built** `jsonb_build_object(...)` containing only
  `name`, `funnelType`, `content` (== `published_content`, never the
  draft `content`), `publicSlug`, `publishedAt`, `publishedVersion`.
  Returns SQL `NULL` (not an error) for a draft, unpublished, or
  nonexistent slug - all three are indistinguishable to the caller by
  design, so a slug's existence can't be probed from its
  published/unpublished status.
- **`submit_funnel_lead(p_slug, p_name, p_email, p_phone, p_message)
  returns jsonb`** - a second `SECURITY DEFINER` function, also granted
  to `anon`. Validates required-contact-method, email format, and field
  lengths server-side (never trusting client-side validation alone),
  confirms the funnel is currently published by slug, and only then
  inserts into `funnel_leads` with `user_id` set to the **funnel owner's**
  id (matching the existing schema, where `funnel_leads.user_id` has
  always meant "whose funnel this lead belongs to," not "who submitted
  it"). `funnel_leads` itself still has **zero** anonymous-insert RLS
  policy - exactly as Phase 5's own migration comments anticipated - the
  function's `SECURITY DEFINER` privilege is what allows the insert, not
  a weakened policy.

Both functions were smoke-tested directly (no test user needed, since
they're callable with just the anon key and arbitrary parameters):
`get_public_funnel('does-not-exist')` returns `null`; 
`submit_funnel_lead('does-not-exist', ...)` returns
`{"success":false,"code":"NOT_FOUND",...}`.

## Public lead form

`PublicLeadFormWidget` (`lib/features/funnel_generation/presentation/widgets/public_lead_form_widget.dart`)
is the anonymous counterpart to Phase 5's `LeadFormWidget` - same
Name/Email/Phone/Message fields and validators
(`Validators.leadEmail`/`leadPhone`, requiring at least one contact
method), but submits through `PublicLeadFormController` →
`FunnelLeadsRepository.submitPublicLead` → the `submit_funnel_lead` RPC,
never a direct table insert. Kept as an entirely separate
controller/widget from the authenticated-owner path so the Phase 5
behavior (already tested) can never regress from a public-facing change.
`FunnelRenderer` picks whichever widget is appropriate based on whether
it was given a `publicSlug` (public view) or a `funnelId` (owner preview).

### Lead success state

`PublicLeadFormController.submit()` no-ops (returns `false` immediately,
without calling the repository) if a submission is already in flight,
so a fast double-tap can never fire two requests purely from a UI race -
this is on top of (not instead of) `submit_funnel_lead`'s own
60-second same-email duplicate guard, which protects against retries
across separate app sessions/requests too. On success, the form shows
"Thank you! Your information has been submitted successfully." with a
"Submit another" action to explicitly reset; on failure, the backend's
specific message (e.g. "Please enter a valid email address.") is shown
in place of the form, not a generic error, and the network path already
distinguishes between validation failure, not-found, and network
failure at the repository layer.

## Public appointment CTA

Unchanged from Phase 5's `appointment_cta` section type - `FunnelRenderer`
renders it identically on the public view (it never checked `funnelId`
vs `publicSlug` for anything except the lead form). No calendar provider
integration was added or implied; the CTA remains exactly what it was, a
configurable button/text pair - nothing pretends a booking exists.

## Share functionality

`PublishStatusCard` provides Copy Link (`Clipboard.setData`) and Share
(`SharePlus.instance.share(ShareParams(text: url))`, the same `share_plus`
API already used elsewhere in the app) for a published funnel's URL,
both on the post-publish success dialog and on the persistent status
card once a slug exists. The URL is always built via
`EnvConfig.publicFunnelUrl(slug)` - see "Environment / secrets" below.

## Public preview

The Funnel Editor's "Preview Published Version" button and the post-publish
success dialog's "View Published Funnel" button both navigate to
`PublicFunnelViewScreen` - the *exact* screen and RPC path a real visitor
would use, not a separate "simulated" preview. This is a deliberate
design choice: previewing something different from what's actually public
would defeat the purpose of a preview. If the draft has diverged from the
published snapshot, the editor's own status card already surfaces "you
have unsaved changes since this was last published" so the owner knows
*before* tapping preview that they're about to see the last-published
version, not their latest edits - publishing is never triggered
automatically to make the preview "match."

## Publish validation

`publish-funnel`'s `validateForPublish()` checks, before writing anything:
- The funnel has a non-empty name.
- At least one visible section exists.
- If a `hero` section exists, it has a non-empty `headline`.
- If a `final_cta` or `appointment_cta` section exists, it has non-empty
  CTA/headline text.

Failures return `VALIDATION_FAILED` with a specific, actionable message
(e.g. "Your funnel cannot be published because the CTA section is missing
required text.") - `errors` (plural) is also included for every failing
rule at once, so the UI could show all of them, though today only the
first is surfaced. This is deliberately lightweight: `content` already
passed `FunnelSchemaValidator`/`validateFunnelResponse` once at
generation time, so this only re-checks things a manual edit could break
afterward (e.g. clearing the hero headline, hiding every section).

## Image and video assets

Reuses Phase 2/5's existing signed-URL delivery from the private
`app-storage` bucket - no new bucket, no asset migration. `FunnelRenderer`
already wraps every `Image.network` call in an `errorBuilder` that
collapses to nothing rather than crashing (confirmed unchanged, verified
by reading the renderer directly), so a broken/expired image URL degrades
gracefully instead of breaking the page.

**Known gap, not fixed in this phase:** the signed URLs currently baked
into a funnel's `content` (and therefore into `published_content` too)
by `generate-funnel` at generation time expire after **1 hour**. This was
an acceptable limitation for Phase 5 (an authenticated owner regenerating
a URL on demand), but it means a published funnel's hero/logo image can
stop loading well before the page itself is unpublished. Properly solving
this (e.g. re-signing with a long expiry at publish time, or copying
images into dedicated public storage) requires reconstructing the
original storage path from an already-resolved signed URL, which the
current schema doesn't retain - out of scope to retrofit safely in this
phase. Documented here as future work; the renderer's existing
`errorBuilder` ensures this degrades to "missing image," never a crash.

## SEO metadata architecture

Phase 5's `FunnelSeo` (`title`, `description`, `ogTitle`, `ogDescription`)
already exists on every funnel and is preserved unchanged through
publishing (it's part of `content`/`published_content`). Nothing in the
Android app itself consumes these fields for SEO purposes - they only
become meaningful once a real web deployment renders `<title>`/
`<meta description>`/Open Graph tags from `get_public_funnel`'s response.
That deployment should map: `content.seo.title` → `<title>`,
`content.seo.description` → `<meta name="description">`,
`content.seo.ogTitle`/`ogDescription` → `og:title`/`og:description`, and
(not yet supported by the schema) a future `content.seo.ogImage` for the
social preview image.

## Public error pages

`PublicFunnelViewScreen` covers exactly the states the brief asked for:
"Funnel not found" (draft/unpublished/nonexistent slug, indistinguishable
on purpose), a distinct retryable error state for genuine
network/server failures ("Something went wrong loading this page."),
and a loading state. No raw database error, stack trace, or exception
message is ever shown to a public visitor - `AppErrorWidget`'s `message`
is always the same friendly string regardless of the underlying cause.

## Owner publishing dashboard

Covered by `PublishStatusCard` (Funnel Editor) and the new badge on
`GenerationDetailScreen`'s funnel summary - see "Publish button" above.

## Security / RLS

No existing RLS policy was weakened or removed. Summary of what changed
and what didn't:

| Table/function | Change |
|---|---|
| `funnels` (RLS) | **Unchanged** - still owner-only select/insert/update/delete from Phase 5. No `to anon` policy added. |
| `funnel_leads` (RLS) | **Unchanged** - still zero anonymous-insert policy, owner-only select/insert/delete. |
| `get_public_funnel` (new) | `SECURITY DEFINER`, granted to `anon`+`authenticated` - the ONLY path to public funnel data, and it hand-picks safe fields only. |
| `submit_funnel_lead` (new) | `SECURITY DEFINER`, granted to `anon`+`authenticated` - the ONLY path for a public lead insert. |
| `publish-funnel` (Edge Function) | `verify_jwt: true`; uses only the caller's own user-scoped (RLS-respecting) client - it can never read or publish a funnel it doesn't own, and never uses a service-role client at all. |

**Verified without creating a SQL test user** (per this phase's explicit
constraint): both new RPCs respond correctly to a nonexistent slug using
only the anon key and arbitrary parameters (see "Public data access"
above for the exact calls and results). **Not verified live in this
phase** (would require either a real signed-up user or a temporary test
fixture, both of which this phase's brief explicitly disallowed
creating): "owner can publish own funnel," "user cannot publish another
user's funnel," "public cannot access a real draft/unpublished funnel,"
end-to-end with real rows. The RLS/SECURITY DEFINER design reasoning for
each of these is documented above and in the migration's own comments;
end-to-end confirmation with real data is a recommended next step once
either a test account can be created or the pre-existing Splash/Auth
issue no longer blocks normal in-app sign-up.

## Edge Functions

Only one new function was created - `publish-funnel` - after concluding
that `get-public-funnel` and `submit-funnel-lead` (both suggested as
"potential" functions in the brief) are equally secure and simpler as
direct RPC calls (`supabase.rpc(...)`) from the client using just the
anon key, since the actual security boundary is the `SECURITY DEFINER`
SQL function either way; wrapping them in an Edge Function would add a
network hop and a second thing to deploy/maintain without adding any
security. "Only create functions that are actually necessary" (the
brief's own words) is the reasoning for this scope reduction.

`publish-funnel` follows the established `generate-funnel` security
pattern exactly: JWT-derived identity only, a single user-scoped client
for every read/write (RLS enforces ownership), a `funnelId` is never
treated as authorization by itself, no service-role client at all (the
real Postgres unique index on `public_slug` is what actually enforces
slug uniqueness, not an elevated-privilege pre-check).

## Rate limiting / abuse protection

Implemented, deliberately minimal:
- Server-side validation of every field (length limits, email format,
  required-contact-method) inside `submit_funnel_lead` - never trusts the
  client's own `Validators.leadEmail`/`leadPhone` checks alone.
- A 60-second same-email-same-funnel duplicate guard inside
  `submit_funnel_lead` (treats a repeat as a silent success, not an
  error, from the visitor's perspective).
- A double-submit guard in `PublicLeadFormController.submit()` itself
  (no-ops while already submitting).

**Not implemented, documented as future work:** IP-based rate limiting,
CAPTCHA, or any broader anti-bot system. A production deployment fronted
by a real web server/CDN should add standard rate limiting at that layer
(e.g. Cloudflare, or Supabase's own Edge Function rate limits if this
were moved behind one) before public launch at scale.

## Analytics foundation

No new table or tracking code was added in this phase - "do not build a
full analytics system" was explicit in the brief, and there was no
existing analytics infrastructure to extend. Recommended minimal future
addition: a `funnel_page_views` table (`id, funnel_id, viewed_at`, maybe
`referrer`) written to by `get_public_funnel` itself (already the single
choke point every page view passes through) or by a lightweight
follow-up RPC, plus a `count(*) from funnel_leads where funnel_id = ...`
query for lead counts (no new table needed for that part - it already
exists).

## Export

`FunnelEditorScreen`'s app bar gained a "More" menu with "Export JSON,"
which shares (`share_plus`) `FunnelSchema.toJson()` - the exact same
content already visible/editable in the editor - as a `.json` file.
Exports **only** the funnel's own content: never `id`/`user_id`/other row
metadata, never credit/subscription data, never any Supabase credential.
HTML export was considered and intentionally not built - it would need
either a bundled HTML template engine or reusing `FunnelRenderer`'s
section logic in a second, HTML-emitting form, both meaningful scope for
a "do not compromise architecture merely to implement it" phase; the
JSON export plus the fact that any future HTML exporter can walk the
exact same `sections[]` list `FunnelRenderer` already knows how to
interpret (unchanged from Phase 5's own note about this) covers the
brief's "at minimum" requirement.

## Duplicate Funnel / Delete Funnel compatibility

Both already work correctly with publishing **without any code change**,
by construction:
- **Duplicate**: `FunnelDuplicateController.duplicate()` inserts a
  brand-new `funnels` row via `insertFunnel()`, which never sets any
  publishing column - they default to `published=false`,
  `public_slug=null`, `published_version=0` at the database level. A
  duplicated funnel can never accidentally inherit the original's
  published state or public slug.
- **Delete**: a funnel is deleted only via its `generations` row's
  existing `on delete cascade` foreign key (unchanged since Phase 5) -
  deleting the `generations` row deletes the entire `funnels` row,
  publishing columns included. `get_public_funnel(slug)` for that now-gone
  slug simply returns `null` (the same "not found" response as an
  unpublished funnel), since it queries live, not from a cache - there is
  no orphaned public content possible.

## UI/UX and accessibility

All new widgets use Material 3 components already used elsewhere in the
app (`Card`, `FilledButton`/`OutlinedButton`, `AlertDialog`,
`CircularProgressIndicator`) rather than introducing new patterns. Every
interactive element has a text label (buttons say "Publish"/"Republish"/
"Unpublish"/"Copy Link"/"Share"/"Preview Published Version" outright,
never an icon-only affordance without a tooltip). Confirmation dialogs
state the concrete consequence in plain language (e.g. "Visitors will no
longer be able to access the public page."). Loading states use the
existing `LoadingWidget`/inline `CircularProgressIndicator` convention.
No existing Phase 1-6 screen's layout was changed beyond the two additive
insertions described above (the editor's status card, the generation
detail funnel card's badge).

## Testing

**Unit tests** (`test/features/funnel_generation/funnel_publishing_model_test.dart`,
`funnel_publish_controller_test.dart`, `public_lead_form_controller_test.dart`):
`FunnelModel.fromJson`'s publishing-field parsing and defaults,
`hasUnpublishedChanges` in all four states (never published, just
published, edited-since-publish, unpublished-with-stale-edit),
`copyWith` field preservation, `PublicFunnelView.fromJson`,
`EnvConfig.publicFunnelUrl`'s no-fake-URL fallback,
`FunnelPublishController.publish/unpublish` (first publish, republish
reusing the slug, validation-failure surfacing, unpublish preserving the
slug), and `PublicLeadFormController.submit` (missing-contact rejection,
success, backend-validation-message surfacing, and the double-submit
no-op guard).

**Widget tests** (`public_funnel_view_screen_test.dart`): loading state,
successful render of published content (and that the owner-preview
banner never appears for a signed-out visitor), the not-found state for
a null result, and a genuine error state shown distinctly from
not-found with a working retry action.

**Updated existing tests**: every existing fake `FunnelRepository`/
`FunnelLeadsRepository` implementation across
`funnel_duplicate_controller_test.dart`, `funnel_editor_screen_test.dart`,
`funnel_editor_controller_test.dart`, and `lead_form_widget_test.dart`
was extended with the new interface methods (as `throw
UnimplementedError()` where irrelevant to that test) so the interface
change compiles - no existing test assertion was altered, and all
continue to pass unchanged.

**Not done, and why**: live end-to-end security tests against real rows
(owner-publish, cross-user-denial, draft/unpublished public-access
denial) - see "Security / RLS" above for the exact reasoning
(no-test-user constraint) and what was verified instead.

## Environment / secrets

New config value: `PUBLIC_APP_URL` - the production domain published
funnels are served from (e.g. `https://your-domain.example`). Not a
secret (it's just a URL prefix used to build a display/share link) - safe
to ship in the client build like `SUPABASE_URL`/`SUPABASE_ANON_KEY`
already are. Added to:
- `lib/core/config/env_config.dart` (`EnvConfig.publicAppUrl`,
  `EnvConfig.publicFunnelUrl(slug)`) - `String.fromEnvironment`, defaults
  to empty.
- `env/dev.json.example` and `env/dev.json` (empty string - **never** a
  fake-looking production URL; an unconfigured build shows `/f/<slug>`
  as a relative path instead, so nothing displayed ever looks like a
  working link when it isn't one).
- `.env.example` - documented both as a Flutter client value and as the
  matching `publish-funnel` Edge Function secret
  (`supabase secrets set PUBLIC_APP_URL=...`), which is where the
  `publicUrl` field in that function's response is actually built.

No service-role key, AI provider key, or any other secret was added to
Flutter or to this documentation with a real value - every value shown
in this doc and in `.env.example` is a name only.

## Phase 6 compatibility

Verified by reading `publish-funnel`/the new RPCs end to end: **none of
them call `reserve_credits`, `finalize_generation_charge`,
`refund_generation_credits`, or any other Phase 6 billing function.**
Publishing, unpublishing, republishing, viewing a public funnel, and
submitting a lead all cost **zero** AI credits - the brief's explicit
requirement. Credits are only ever charged by the four `generate-*`
functions on an actual AI generation call, which this phase does not
touch. Existing credits/usage/subscription/image/music/video/funnel-
generation/projects/history/storage/auth/RLS behavior is unmodified
except for the two additive changes already described (funnel model
gaining fields, one narrow router redirect exception).

## Known limitations

- No real public web deployment exists yet - `/f/:slug` works fully
  inside this Android app but is not reachable from an external browser.
  See "Future production architecture" below.
- Signed image URLs baked into a funnel's content expire after 1 hour
  (pre-existing Phase 5 behavior); a published page's images can go
  stale before the page itself is unpublished. See "Image and video
  assets" above.
- No IP-based rate limiting or CAPTCHA on public lead submission - only
  the minimal server-side validation/duplicate-guard described above.
- No analytics/page-view tracking exists yet - documented as future
  architecture only.
- Only the first validation error is surfaced to the UI today, though
  the backend already returns the full list (`errors: string[]`).
- Live end-to-end RLS/security verification with real rows was not
  performed in this phase (see "Security / RLS").
- **The pre-existing Splash → Login startup hang**: a specific cause
  (a race between two independently-subscribed auth-state streams
  driving the router) was found and fixed in a prior session
  (commit `beeee47`, already merged, unrelated to this phase's own
  work) and was confirmed working at that time. This phase made no
  further changes to that mechanism beyond the one narrow
  `isPublicFunnelRoute` redirect exception described in "Public
  routing" above. **Emulator verification for Phase 7 itself was
  attempted in this session and was blocked by a separate, still-
  unresolved environment/tooling instability** (the emulator process
  itself crashing/disconnecting during launch, evidenced by
  `bluetooth hardware error` and `device not found` failures unrelated
  to any Dart/app code) - not a recurrence of the original auth-race
  hang. This is a host/emulator-level issue in this specific sandboxed
  environment, not something fixable from application code.

## Future production architecture (for a real public web deployment)

To make `https://your-domain.example/f/my-funnel` actually work in a
browser, a future phase needs a real web frontend (a small server-rendered
or static-site app, not necessarily this Flutter codebase) that:
1. Resolves the `:slug` from the URL path.
2. Calls `get_public_funnel(slug)` via the Supabase JS/REST client using
   only the public anon key (identical call to what this phase's Dart
   code already makes).
3. Renders the returned `content` sections as real HTML (reusing the
   same section-type contract `FunnelRenderer` already implements, just
   in a different render target) and sets `<title>`/meta tags from
   `content.seo`.
4. Posts lead-form submissions to `submit_funnel_lead(slug, ...)`, again
   via the anon key - no custom backend needed for that either.
5. Is deployed at the domain configured as `PUBLIC_APP_URL`.

Nothing about this phase's database/RPC design would need to change to
support that - the public data-access layer was built anticipating
exactly this from the start.
