# Image generation (Phase 2)

Phase 2 adds a fully working AI Image Generation feature on top of the
Phase 1 foundation. This document covers the parts specific to Phase 2;
see [architecture.md](architecture.md) for the general app architecture and
[ai-integration.md](ai-integration.md) for the provider-abstraction pattern
this feature is an instance of.

## What was reused vs. added

**Reused unchanged:** Supabase Auth/session, the `generations` and
`generation_files` tables, `GenerationRepository`, `GenerationOrchestrator`,
`CreationType`/`GenerationStatus`, the Create tab's category picker, the
History screen and its filters, the credits summary, theme, navigation
shell, error handling, `FileUploadService`, the private `app-storage`
bucket.

**Added:**
- `supabase/functions/generate-image/` - the Edge Function.
- `lib/features/generation/services/edge_function_image_provider.dart` -
  the real `ImageAIProvider` implementation wired into
  `imageAIProviderProvider` (`generation_providers.dart`), replacing the
  Phase 1 mock for the Image category only. Every other category is
  untouched.
- `lib/features/image_generation/` - the dedicated "AI Image Generator"
  screen, its settings/reference-image models, and the reference-image
  validator.
- Two small, additive extensions to existing Phase 1 types:
  `AIGenerationResult.additionalFiles` (for multi-image results) and
  `GenerationRepository.deleteGenerationAndFiles` (storage-aware delete).
  Both are opt-in - nothing that doesn't use them changes behavior.

## Request flow

```
ImageGeneratorScreen
  -> (optional) FileUploadService uploads the reference image to
     {user_id}/uploads/... in the private app-storage bucket
  -> CreateGenerationController.submit(type: image, options: settings.toJson())
  -> GenerationOrchestrator.generate()
       - creates the `generations` row (status: pending) via the
         authenticated client - RLS enforces user_id = auth.uid()
       - sets status: processing
       - calls EdgeFunctionImageProvider.generate()
           -> supabase.functions.invoke('generate-image', body: {
                prompt, referenceImagePath, settings
              })
              == Supabase Edge Function == (see below)
           <- { success, images: [...], provider, model, metadata }
       - persists result_url/thumbnail_url/metadata, status: completed
         (or error_message, status: failed, on any failure)
       - attaches any images beyond the first to `generation_files`
GenerationDetailScreen reads the row back - Download/Share/Regenerate/Delete
```

### Why the Edge Function doesn't write to `generations` itself

The step list in the original brief has the Edge Function "update the
generation record." This implementation instead keeps a single writer for
that table - the already-tested Phase 1 `GenerationOrchestrator` - and has
the Edge Function return a plain result payload. Reasons:

1. No race between the Edge Function's write and the orchestrator's own
   write to the same row.
2. Zero new code paths for the pending -> processing -> completed/failed
   state machine - it's the exact same logic every other generation type
   already uses and Phase 1 already has tests for.
3. The Edge Function still owns everything security-sensitive: identity,
   credits, the provider call, and the Storage upload.

## The Edge Function (`supabase/functions/generate-image`)

```
index.ts            - request handling, auth, validation, credits, storage upload
types.ts             - shared request/response types
providers/
  provider.ts        - ImageGenerationProvider interface
  mock_provider.ts    - development-mode provider (default)
  openai_provider.ts  - real provider (OpenAI Images API)
  index.ts            - picks mock vs. openai from secrets
```

Security model:
- **Identity**: derived only from `userClient.auth.getUser()` after
  forwarding the caller's own `Authorization` header - the request body has
  no `user_id` field, and nothing in it is trusted for authorization.
  `verify_jwt: true` is also set at the platform level, so an unauthenticated
  request is rejected before the function's own code even runs (confirmed:
  a request with no `Authorization` header gets `401
  UNAUTHORIZED_NO_AUTH_HEADER` from the gateway itself).
- **Storage**: uploads and reference-image downloads use a client built
  from the caller's own JWT, so the existing `app-storage` bucket RLS
  policies (first path segment = `auth.uid()`) apply exactly as if Flutter
  called Storage directly - this function cannot read or write another
  user's files, by construction, not just by convention.
- **Credits**: `subscriptions`/`credit_transactions` are read and written
  with the service-role client, because (by design, since Phase 1) those
  tables have no client-writable RLS policy at all. This is the one place
  elevated privileges are used, and it's scoped to exactly those two tables.
- **Rate limiting**: rejects a request if the caller already has 2+ image
  generations in `processing` status within the last 15 seconds (the
  request that's already in flight counts as 1, so this only catches a
  genuine duplicate/overlapping call). Real usage limits are the credits
  system itself (`subscriptions.credits_limit` differs per plan - `free`
  ships with 50 from the Phase 1 signup trigger).
- **Errors**: provider/database errors are caught and mapped to a short
  friendly `error` string plus a `code`; raw provider responses, stack
  traces, and secrets are never included in the response. Technical detail
  goes to `console.error` (visible via `supabase functions logs
  generate-image`), never to the client.

## AI provider setup

The Edge Function's own provider selection is controlled entirely by
Supabase secrets - the Flutter app never knows or cares which one is active:

| Secret | Values | Default |
|---|---|---|
| `AI_IMAGE_PROVIDER` | `mock` \| `openai` | `mock` |
| `AI_IMAGE_MODEL` | provider-specific model id | `gpt-image-1` (when provider=openai) |
| `AI_IMAGE_API_KEY` | the provider's secret key (falls back to `OPENAI_API_KEY` if set) | - |

**Mock mode** (default, and what this project currently runs with - no key
has been configured): returns a labelled placeholder image fetched from
`placehold.co`, still going through the full upload/DB/history pipeline. No
paid API is ever called. Safe to leave on indefinitely for development.

**To enable real generation:**
```bash
supabase secrets set AI_IMAGE_PROVIDER=openai
supabase secrets set AI_IMAGE_API_KEY=sk-...
# optional - defaults to gpt-image-1
supabase secrets set AI_IMAGE_MODEL=gpt-image-1
supabase functions deploy generate-image
```
Setting `AI_IMAGE_PROVIDER=openai` **without** a key configured is treated
as a deployment mistake, not a silent fallback: the function returns a clear
`CONFIGURATION_ERROR` instead of quietly serving mock images, so a
misconfigured production deploy is caught immediately rather than shipping
placeholder images unnoticed.

### About the OpenAI implementation - please verify before production use

This was implemented against OpenAI's publicly documented Images API
(`POST /v1/images/generations`, model `gpt-image-1`) as of the time this
was written, cross-checked against available documentation at the time.
**AI vendor APIs change.** Before relying on this in production:

1. Re-check https://platform.openai.com/docs/api-reference/images against
   `supabase/functions/generate-image/providers/openai_provider.ts`.
2. Known, deliberate gaps (mapped/handled, not silently pretended to work):
   - `style` (realistic/cinematic/anime/...) has no native gpt-image-1
     parameter - it's prepended to the prompt text instead.
   - `4:3` has no native gpt-image-1 size - it falls back to `1024x1024`.
   - The reference-image path uses `/v1/images/edits` (a different,
     multipart request shape than text-to-image `/v1/images/generations`)
     and does not forward `quality`.
3. If OpenAI isn't the provider you want, implement
   `ImageGenerationProvider` (see `providers/provider.ts`) for your vendor
   and add one `case` to `providers/index.ts` - nothing else changes.

## Settings -> provider mapping

| Setting | gpt-image-1 mapping |
|---|---|
| Aspect ratio 1:1 / 16:9 / 9:16 | `size` = `1024x1024` / `1536x1024` / `1024x1536` |
| Aspect ratio 4:3 | no native size - falls back to `1024x1024` |
| Quality standard / high | `quality` = `medium` / `high` |
| Style | folded into the prompt text (no native parameter) |
| Number of images (1-4) | `n` (gpt-image-1 supports multiple images per call) |

## Storage

Generated images are stored in the existing private `app-storage` bucket
(Phase 1) at `{user_id}/generations/{request_id}/result[-N].{ext}`, where
`request_id` is a fresh UUID per generation call (not necessarily equal to
the `generations.id` row, which the Edge Function never touches - see
above). The Flutter app never calls `getPublicUrl()`; it always receives a
signed URL (1 hour expiry) from the Edge Function. The primary image's
storage path is kept in `generations.metadata.storagePath` so
`deleteGenerationAndFiles()` can remove it later; extra images (2nd-4th) get
their own `generation_files` row with a proper `storage_path` column.

## How to test

```bash
flutter analyze
flutter test
```

To exercise the real pipeline end to end in mock mode (no key needed):
sign in to the app, go to Create -> Image, enter a prompt, tap Generate.
You should see a placeholder image appear, tagged `mock`/`mock-image-v1` in
the detail screen, and it should show up in History -> filter: Image.

To test the Edge Function directly:
```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/generate-image" \
  -H "Authorization: Bearer <a real user JWT, e.g. from the app's session>" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "a modern pharmacy advertisement"}'
```
A request with no `Authorization` header should get `401` - this is worth
re-checking after any redeploy.

## How to deploy the Edge Function

```bash
supabase link --project-ref <your-project-ref>
supabase functions deploy generate-image
```
(For this project, it's already deployed - see the README's Supabase
configuration table for the project ref.)
