# Funnel generation (Phase 5)

Phase 5 adds an AI Funnel/Landing Page Generator on top of Phase 1-4,
reusing the same architecture as
[image-generation.md](image-generation.md),
[music-generation.md](music-generation.md), and
[video-generation.md](video-generation.md) - read at least one of those
first; this one only calls out what's different. The key architectural
difference from every prior phase: a funnel's "result" isn't a single
file - it's a **structured, versioned JSON document** with its own
dedicated table, editor, and renderer, deliberately never raw HTML.

## What was reused vs. added

**Reused unchanged:** Supabase Auth/session, the `generations` table
(`generation_type = "funnel"` - already in Phase 1's check constraint),
`GenerationRepository`, `GenerationOrchestrator` (extended additively - see
below), `CreationType`, the Create tab's category picker, History and its
filters, the credits summary, the shared `GenerationDetailScreen`
(extended with a funnel summary card, not duplicated), theme, navigation
shell, error handling, the private `app-storage` bucket, and Phase 2's
`ReferenceImage` model/validator (reused for the Logo and Product/Reference
image uploads).

**Added:**
- `supabase/functions/generate-funnel/` - authenticates, validates,
  checks credits, calls the LLM provider, validates/corrects its response
  into a `FunnelSchema`, stores it, returns the result.
- `funnels` and `funnel_leads` tables (new migration
  `20250101060000_funnels.sql`).
- `lib/features/generation/services/edge_function_funnel_provider.dart` -
  the real `FunnelAIProvider`, wired into `funnelAIProviderProvider`.
- `AIGenerationRequest.generationId` (new, additive field) - the one
  extension to the shared provider abstraction this phase needed (see
  "Why the orchestrator needed one new field" below).
- `lib/features/funnel_generation/` - the funnel schema/validator/models,
  repositories, the "AI Funnel Builder" generator screen, the structured
  editor, the responsive preview, the `FunnelRenderer` (structured Flutter
  widgets, never HTML), and the reusable `LeadFormWidget`.
- `GenerationDetailScreen` gained a funnel branch: instead of showing raw
  `resultText`, it looks up the linked `FunnelModel` and shows a summary
  card with Preview/Edit/Duplicate Funnel actions.
- `Validators.funnelPrompt`, `Validators.businessName`,
  `Validators.leadEmail`/`leadPhone`.

## The funnel schema

Conceptually (see `lib/features/funnel_generation/data/models/funnel_schema.dart`
and the Deno mirror in `supabase/functions/generate-funnel/types.ts` -
kept in sync by hand, since Deno and Dart share no code in this project):

```
FunnelSchema {
  version: 1                     // schema versioning - see below
  name: string
  type: string                   // one of 15 funnel types (see below), or "custom"
  metadata: { business_name, business_type, target_audience, goal, offer, cta }
  theme: { primaryColor, secondaryColor, backgroundColor, textColor, fontFamily, logoUrl? }
  sections: [ { id, type, visible, content: {...} } ]
  seo: { title, description, ogTitle, ogDescription }
  settings: { showNavigation, enableLeadCapture }
}
```

Section `type` is one of: `hero`, `navigation`, `benefits`, `features`,
`services`, `products`, `pricing`, `testimonials`, `statistics`, `about`,
`faq`, `contact`, `lead_form`, `appointment_cta`, `final_cta`, `footer`, or
`custom`. `content`'s shape depends on `type` (e.g. hero:
`headline`/`subheadline`/`cta`/`image`; faq: `title` + `items[]` of
`{question, answer}`) - see `FunnelRenderer` for the exact fields each
section type reads.

**Schema versioning:** `version` is always set to `1` by
`validateFunnelResponse()`/`FunnelSchemaValidator.validate()` - it is
never trusted from the AI's raw output. A future schema version (e.g.
adding a new top-level field) bumps this constant and the validator gains
a branch for it; old, already-stored funnels keep their recorded
`schema_version` and continue rendering exactly as before, since the
renderer only reads fields it knows about and ignores the rest.

## JSON validation (never blindly render malformed data)

Both sides run their own copy of the same validation/correction logic:
- **Server-side, authoritative:** `supabase/functions/generate-funnel/schema.ts`
  - `validateFunnelResponse()`.
- **Client-side, defensive:** `lib/features/funnel_generation/data/models/funnel_schema_validator.dart`
  - `FunnelSchemaValidator.validate()`, applied automatically inside
    `FunnelModel.fromJson()` - there is no code path from a raw
    `funnels.content` row into the UI that skips it.

What "safe correction" means in practice: an invalid theme color falls
back to a sensible default (not the whole theme); a missing SEO
title/description falls back to the funnel's name; a section with an
unrecognized `type` is dropped (not rendered, not stored as-is); the
funnel `type`/`goal` fall back to the value the user actually selected in
the UI if the AI's value isn't one of the known enums. The **only** thing
that cannot be safely defaulted, and therefore throws
(`INVALID_AI_RESPONSE` server-side, `FunnelValidationException`
client-side), is ending up with **zero usable sections** after
correction - that funnel is never stored (server-side) or never rendered
(client-side).

## Funnel provider architecture

```
lib/features/generation/services/ai_provider.dart
  FunnelAIProvider extends AIProvider          # unchanged interface

lib/features/generation/services/edge_function_funnel_provider.dart
  EdgeFunctionFunnelProvider implements FunnelAIProvider
    -> calls generate-funnel, maps { funnelId, funnel: {...}, provider, model }
       into AIGenerationResult(resultText: funnel.name, thumbnailUrl: logoUrl, metadata: {...})

supabase/functions/generate-funnel/providers/
  provider.ts          # FunnelGenerationProvider interface
  mock_provider.ts      # deterministic, template-based (default) - builds a
                         # full funnel straight from the business fields,
                         # no external call
  openai_provider.ts     # real provider - OpenAI Chat Completions, JSON mode
  index.ts                # picks mock vs. openai from secrets
```

Not coupled to one AI vendor: `FunnelGenerationProvider.generate()` returns
`{ raw, providerName, modelName, metadata }` where `raw` is whatever
(possibly malformed) JSON-ish value the model produced - `schema.ts`'s
validator is what turns that into a trustworthy `FunnelSchema`, regardless
of which provider produced it.

### Why the orchestrator needed one new field

Every prior phase's Edge Function returns its result to the orchestrator,
which persists it onto the *existing* `generations` row it already
created. A funnel's result additionally needs to be **stored as a new row
in its own table** (`funnels`), linked back to that same generation - and
the Edge Function, not the Dart client, is the trusted place to do that
storing (see "The Edge Function" below). To link the two without trusting
a client-supplied id, `generate-funnel` needs to know *which* generation
it's fulfilling. So `AIGenerationRequest` gained one new, optional,
additive field: `generationId` - set by `GenerationOrchestrator` to the id
of the row it just created, before calling the provider. Every other
provider (image/music/video) ignores this field entirely; nothing about
their behavior changes.

## The Edge Function (`supabase/functions/generate-funnel`)

```
Flutter -> generate-funnel
  -> authenticate (JWT)
  -> validate request (prompt, funnelType, businessInfo)
  -> verify the generationId belongs to this caller and is a funnel-type
     generation (RLS-backed select; a generationId alone is never treated
     as authorization - same principle as video's job-id verification)
  -> duplicate-request check, credits check
  -> call the configured LLM provider -> raw JSON
  -> validateFunnelResponse() -> FunnelSchema (safe correction or reject)
  -> splice in real Storage-backed logo/product image URLs (never trust
     the AI to have used a real URL - it's told not to include one at all)
  -> INSERT into `funnels` (user-scoped client -> RLS applies)
  -> deduct credits (service-role client, subscriptions/credit_transactions only)
  -> return { success, funnelId, funnel, provider, model, metadata }
```

Security model mirrors every prior Edge Function: JWT-derived identity,
user-scoped client for reads/writes that must respect RLS, a service-role
client scoped *only* to `subscriptions`/`credit_transactions`. The one
structural difference: this function **does write to a table**
(`funnels`) - the single-writer principle from Phase 2 is specifically
about never writing to `generations` from an Edge Function; `funnels` is a
new, dedicated table whose entire purpose is to hold the validated
document this function produces, exactly as the brief's own AI-generation
flow describes ("validate JSON -> store funnel -> return safe result").
Confirmed live: an unauthenticated request gets `401
UNAUTHORIZED_NO_AUTH_HEADER` from the gateway.

- **Credit cost is a flat 4 credits** - between music (3) and video (5), a
  placeholder like every other type's cost until a real cost model is
  needed.
- **Duplicate-request window is 60s** - a funnel is one text/JSON round
  trip, similar order of latency to music.

## AI provider setup

| Secret | Values | Default |
|---|---|---|
| `FUNNEL_GENERATION_PROVIDER` | `mock` \| `openai` | `mock` |
| `FUNNEL_GENERATION_MODEL` | provider-specific model id | `gpt-4o-mini` |
| `FUNNEL_GENERATION_API_KEY` | the provider's secret key (falls back to `OPENAI_API_KEY`) | - |

**Mock mode** (default, and what this project currently runs with - no key
configured): builds a complete, realistic funnel document directly from
the business fields the user typed (name/product/audience/offer/CTA),
choosing extra sections (`lead_form`, `appointment_cta`, `pricing`) based
on the selected goal - no external network call, runs through the full
real pipeline (validation, Storage-backed images if uploaded, database
insert, editor, preview). No paid API is ever called.

**To enable real generation:**
```bash
supabase secrets set FUNNEL_GENERATION_PROVIDER=openai
supabase secrets set FUNNEL_GENERATION_API_KEY=sk-...
supabase functions deploy generate-funnel
```
As with every other type, setting the provider to `openai` without a key
fails loudly (`CONFIGURATION_ERROR`) instead of silently serving mock
output.

### About the OpenAI implementation - please verify before production use

Implemented against OpenAI's publicly documented Chat Completions API
(`POST https://api.openai.com/v1/chat/completions`, model default
`gpt-4o-mini`, `response_format: {type: "json_object"}` for guaranteed
JSON output) as of the time this was written, with a system prompt that
spells out the exact target schema and the list of valid funnel
types/goals/section types. **This has not been exercised against a real
API key** - no credentials were available. Before relying on it in
production:

1. Re-check https://platform.openai.com/docs/api-reference/chat against
   `supabase/functions/generate-funnel/providers/openai_provider.ts`.
2. `response_format: json_object` guarantees syntactically valid JSON but
   not that it matches the requested *shape* - that's exactly what
   `validateFunnelResponse()` exists to catch and correct, so this is
   expected defense in depth, not a gap to fix.
3. The model is instructed never to invent an image/logo URL and never to
   present a testimonial as if it were from a real, named person - verify
   this holds up under adversarial prompts before trusting generated copy
   without review.

## Funnel types and goals

15 funnel types (`lead_generation`, `product_sales`, `service_business`,
`appointment_booking`, `event_registration`, `restaurant`, `pharmacy`,
`healthcare`, `real_estate`, `personal_brand`, `agency`, `ecommerce`,
`course`, `portfolio`, `custom`) and 8 goals (`generate_leads`,
`sell_product`, `book_appointment`, `collect_contact_info`,
`promote_service`, `build_brand_awareness`, `event_registration`,
`custom`) - see `FunnelType`/`FunnelGoal` in `funnel_schema.dart` (Dart)
and `VALID_FUNNEL_TYPES`/`VALID_GOALS` in `schema.ts` (Deno). The goal
drives which sections a generated funnel includes - the brief's "do not
force every section into every funnel" is implemented both in the mock
provider's own section-selection logic and as an instruction to the real
LLM provider; nothing hard-codes a fixed section list.

## Database

```
funnels
  id, user_id, project_id, generation_id (unique, FK -> generations, on delete cascade),
  name, description, funnel_type, status ('draft'|'archived'),
  schema_version, content (jsonb - the full FunnelSchema), thumbnail_url,
  created_at, updated_at

funnel_leads
  id, funnel_id (FK -> funnels), user_id (the FUNNEL OWNER, not the
  visitor), name, email, phone, message, created_at
```

**Why `funnels.generation_id` has `on delete cascade`:** deleting a
funnel-type generation through the existing, already-tested
`GenerationRepository.deleteGeneration()`/`deleteGenerationAndFiles()`
(exactly the same call every other type's Delete button already makes)
automatically removes its `funnels` row too - no new delete Edge Function,
RPC, or Dart-side special case was needed. RLS on `funnels` is still
enforced independently (`user_id = auth.uid()` on every operation), since
the editor/preview screens read `funnels` directly, not only through
`generations`.

**Why sections live inside `content` (JSONB) instead of their own
tables:** the brief explicitly asks to avoid "dozens of tables for
individual sections" - the structured JSON is the source of truth, and a
JSONB column with an application-level validator (kept in sync between
Deno and Dart) gives the same safety with far less schema churn as new
section types are added.

**`funnel_leads.user_id` is the funnel owner, not the submitting
visitor** - visitors have no account. This is what lets RLS restrict
reads to "leads belonging to your own funnels" without a join. Phase 5
does not implement public publishing, so there's no anonymous visitor
insert path yet - `LeadFormWidget` submits as the *funnel owner's own*
authenticated session (useful for testing the component against your own
funnel today). A future "publish" phase introducing real anonymous
visitor submissions must add that pathway through a dedicated,
rate-limited Edge Function using the service role - never by widening this
table's RLS to `with check (true)`.

## Storage / image integration

No new bucket. An uploaded Logo or Product/Reference image is uploaded
through the existing `FileUploadService` to `app-storage` exactly like
every other type's reference image, then `generate-funnel` resolves a
signed URL from that existing object and splices it into
`theme.logoUrl`/the hero section's `image` field - it never re-uploads or
duplicates the file. The architecture is equally ready to reference an
image *generated* in Phase 2 (its `generations.metadata.storagePath`)
instead of a fresh upload; Phase 5 doesn't wire up that specific picker
(no "pick from your image history" UI yet), but nothing about the
Edge Function's signed-URL-resolution step would need to change to support
it.

## Video integration (prepared, not implemented)

The section-type list already includes `video` conceptually via `custom`
(any section the renderer doesn't specifically recognize renders as a
generic fallback rather than crashing) - a first-class `video` section
type can be added the same way the others were: a case in
`FunnelRenderer._buildSection()`, an entry in `VALID_SECTION_TYPES`, and a
reference to a Phase 4 `generations` row's `result_url` in its `content`.
Per the brief, this phase does not auto-generate a video during funnel
generation.

## The Funnel Editor

`lib/features/funnel_generation/presentation/screens/funnel_editor_screen.dart`
+ `funnel_providers.dart`'s `FunnelEditorController` (an
`AsyncNotifier.family` that loads one funnel, lets the screen mutate its
in-memory `FunnelSchema`, and persists on Save). Supported edits: rename
the funnel, edit any section's simple text fields (headline, subheadline,
CTA, titles, descriptions - via `SectionEditorDialog`), hide/show a
section, delete a section, add a new section (picked from the full
section-type list, with a sensible default content template per type), and
reorder sections both via `ReorderableListView` drag-and-drop **and**
explicit Move Up/Down buttons (the brief's fallback, kept as a permanent,
always-available control rather than only a temporary stand-in - useful
for accessibility regardless of drag support). List/nested-map content
(e.g. a benefits section's `items[]`) isn't item-editable yet in this
version - shown as a labelled, honest "not editable yet" count rather than
silently dropped, per the brief's "focus on a stable structured editor,
not a full website builder yet."

## Live Preview

`funnel_preview_screen.dart` renders the **same** `FunnelSchema` through
the **same** `FunnelRenderer` for Mobile/Tablet/Desktop - only the
surrounding max-width constraint changes (390px / 768px / unconstrained),
per the brief's "do not create separate hard-coded layouts for every
device." It reads from the *same* live-edited state the Editor holds
(`funnelEditorProvider`), so Preview reflects unsaved edits without a
second network round trip.

## Structured rendering, not HTML

`FunnelRenderer` (`lib/features/funnel_generation/presentation/widgets/funnel_renderer.dart`)
maps each section `type` to its own small, real Flutter widget builder -
`Text`, `Card`, `ExpansionTile`, `ElevatedButton`, etc. No `Html`/WebView
widget is used anywhere in this feature, so there is no HTML-injection/XSS
surface to sanitize in the first place - the brief's "prefer structured
Flutter rendering over arbitrary HTML" is the *only* rendering path that
exists. An unrecognized section type renders as a plain, inert card
showing its title (if any) rather than being skipped silently or crashing.

## Lead Form

`lead_form_widget.dart` + `funnel_providers.dart`'s `LeadFormController`
(states: `initial -> validating (client-side form validation) ->
submitting -> success | error`). Fields: Name, Email, Phone, Message.
Validation requires at least one of Email/Phone (mirroring the
`funnel_leads_has_contact` database constraint, so the user sees a
friendly message before ever hitting it). Submits via
`FunnelLeadsRepository.submitLead()` directly into Supabase - never to any
third-party service.

## History, duplication, project integration

- **History:** funnel-type generations already show up via the existing,
  unmodified History screen/filters (`CreationType.funnel` was already
  wired in Phase 1) - View opens the shared detail screen's funnel summary
  card, which links to Edit/Preview; Duplicate and Delete are exposed
  there too.
- **Duplicate:** `FunnelDuplicateController.duplicate()` creates a *new*
  `generations` row (marked `completed` immediately - no AI call, no
  credit cost, since nothing was actually generated) and a *new* `funnels`
  row copying the original's content (name prefixed "Copy of ..."),
  leaving the original completely untouched.
- **Delete:** reuses the existing `GenerationRepository` delete path - see
  "Why `funnels.generation_id` has `on delete cascade`" above.
- **Projects:** a funnel's `project_id` is copied from its originating
  generation's `project_id` at creation time (read server-side from the
  already-created `generations` row, never trusted from the client) - a
  project containing an image, a music track, a video, and a funnel is
  just four `generations` rows (plus the funnel's own `funnels` row)
  sharing the same `project_id`, exactly as the brief's "CrossCare
  Pharmacy Marketing" example describes. No new project-side code was
  needed.

## Export / publishing architecture (prepared, not implemented)

Because the funnel is a validated, versioned, structured JSON document
(not a pile of ad-hoc state), it is already in the right shape for a
future export/publish pipeline to consume: an HTML exporter would walk
the same `sections[]` list `FunnelRenderer` already knows how to
interpret; a "publish" flow would flip `funnels.status` from `draft` to a
future `published` value and mint a public URL. **None of that is
implemented in Phase 5** - `status` only ever takes `draft`/`archived`
today, there is no public read policy on `funnels`, and no HTML/ZIP export
code exists yet. This is intentional, per the brief's explicit "do not
implement public hosting or custom domains yet."

## How to test

```bash
flutter analyze
flutter test
```

To exercise the real pipeline end to end in mock mode (no key needed):
sign in, go to Create → Funnel, fill in a business description (and
optionally the business fields/logo/product image), pick a funnel type and
goal, tap Generate Funnel. The generation detail screen shows a summary
card with Preview/Edit/Duplicate Funnel, tagged `mock`/`mock-funnel-v2`,
and shows up in History → filter: Funnel.

**Known testing gap:** live authenticated round-trip testing of
`generate-funnel` (the same way `generate-image` was verified live in
Phase 2) could not be completed in this session - only an unauthenticated
`401` gateway check was verified live, confirming `verify_jwt: true` is
active. `EdgeFunctionFunnelProvider`, `FunnelSchemaValidator`,
`FunnelEditorController`, `FunnelDuplicateController`, and the
Generator/Editor/Preview/Section-Editor/Lead-Form widgets are all covered
by unit/widget tests instead, using fake repositories/Edge Function
invokers rather than live network calls. There is currently no automated
test runner for the Deno Edge Function code itself, matching every prior
phase.

## Deployment

```bash
supabase link --project-ref <your-project-ref>
supabase db push               # applies the funnels/funnel_leads migration
supabase functions deploy generate-funnel
```
(For this project, the migration is already applied and the function is
already deployed - see the README's Supabase configuration table.)
