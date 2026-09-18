# Phase 6 — Credits, Usage & Subscription/Monetization Foundation

This document describes the billing **foundation** shipped in Phase 6: credit
balances, an auditable credit ledger, configurable per-generation costs,
usage tracking, DB-driven Free/Pro/Business plans, and the architecture for
a future payment-provider integration. **No real payment processing exists
yet** — this phase intentionally stops short of that. See
[GITHUB_SUPABASE.md](GITHUB_SUPABASE.md) for the general repo/DB workflow
this phase follows.

## Design principle: reuse, don't duplicate

Phase 1 already had `subscriptions.credits_limit`/`credits_used` as the
balance mechanism, and `credit_transactions` as a (thin) ledger. Every
existing Dart read (`CreditsRepository.getSummary`) and every Edge Function's
credit check already depended on those exact columns. Phase 6 **extends**
these two tables rather than introducing a parallel `credit_balances` table,
which the brief's own example schema suggested — a second table would only
create two sources of truth to keep in sync. This decision, and every column
added, is documented inline in the migration itself
(`supabase/migrations/20250101070000_credits_subscriptions.sql`).

New tables were created only where nothing pre-existing served the purpose:
`plans`, `credit_costs`, `usage_records`, `idempotency_keys`, `billing_events`.
Phase 1's `user_usage` table (a monthly aggregate counter that no code had
ever populated) is left completely untouched — `usage_records` is the actual
per-event ledger Phase 6 needed, and removing `user_usage` was out of scope
("do not delete existing").

## Schema changes

### `subscriptions` (extended)
Added: `plan_id` (FK to `plans`), `provider`, `provider_subscription_id`,
`current_period_start`, `current_period_end`, `cancel_at_period_end`,
`lifetime_credits_earned`, `lifetime_credits_used`. The `status` check
constraint was widened to add `trialing`/`paused` (every existing value,
including `active` — which every generate-* Edge Function's credit check
depends on — is kept exactly as-is).

### `credit_transactions` (extended)
Added: `balance_after`, `reference_type`, `idempotency_key`, `metadata`. The
`transaction_type` vocabulary was replaced with the brief's explicit list:
`MONTHLY_GRANT`, `GENERATION_CHARGE`, `REFUND`, `MANUAL_ADJUSTMENT`,
`PURCHASE`, `SUBSCRIPTION_GRANT`, `EXPIRATION`, `PROMOTIONAL_CREDIT`. A
unique index on `(user_id, idempotency_key)` (where not null) is the
database-level backstop for "never double-charge."

### `plans` (new)
`code` (`free`/`pro`/`business`), `name`, `description`, `monthly_credits`,
`price_display` (free text — **no final pricing exists**, deliberately not a
`price_cents` column that would imply a decided price), `active`, `features`
(jsonb). Publicly readable when `active = true`; never client-writable.
Seeded with free=50/pro=500/business=2000 monthly credits — the free-plan
number matches what `handle_new_user()` already hard-coded in Phase 1, so
wiring the trigger to read from this table changed no existing behavior.

### `credit_costs` (new)
`generation_type` (`text`/`image`/`music`/`video`/`funnel`), `variant`
(nullable — every type is flat-rate today; a future per-quality cost is a
new row, not a schema change), `cost`, `active`. Publicly readable, so
Flutter can show "Generate Video — 5 credits" before submitting; never
client-writable. Seeded with the exact numbers every Edge Function already
hard-coded (image=1/music=3/video=5/funnel=4) — moving them here changed
nothing about current pricing, only where the number lives.

### `usage_records` (new)
One row per billable generation event: `generation_id` (unique FK),
`generation_type`, `credits_consumed`, `status`
(`processing`/`completed`/`failed`/`refunded`), `provider`, `metadata`.
This is what the Usage Dashboard's per-type breakdown reads.

### `idempotency_keys` (new)
`user_id`, `key`, `operation`, `status`, `generation_id`, `result`, with a
`unique (user_id, key, operation)` constraint. RLS is enabled with **zero**
policies — no client, not even the owning user, can read or write this
table; only `SECURITY DEFINER` functions (running as the Edge Functions'
service-role calls) touch it. This is the mechanism behind every "exactly
once" guarantee in this phase.

### `billing_events` (new)
A provider webhook/event log for the future payment integration. Nothing
writes to it yet — no real payment provider exists in this phase — but the
table exists so a future `handleWebhook` implementation has somewhere to
record what it received before acting on it.

## Race-safety: the two-simultaneous-requests problem

The brief's explicit test case: a user has 50 credits, and two concurrent
requests each try to charge 40 credits — only one may succeed. This is
solved with a single atomic conditional `UPDATE`:

```sql
update public.subscriptions
   set credits_used = credits_used + p_amount, ...
 where user_id = p_user_id
   and status = 'active'
   and credits_used + p_amount <= credits_limit
returning credits_limit - credits_used into v_balance_after;
```

Postgres row-locks the matching row for the duration of the `UPDATE`. The
second concurrent call blocks until the first commits, then re-evaluates
`credits_used + p_amount <= credits_limit` against the *already-updated*
value — so it correctly sees insufficient credit and fails, with **no**
`SELECT`-then-`UPDATE` window for a race to slip through. This was verified
live against the deployed database (see "Verification performed" below).

## Idempotency: never double-charge, never double-refund

Every credit-moving RPC (`reserve_credits`, `refund_generation_credits`,
`grant_monthly_credits`) takes a `p_idempotency_key` and:

1. Attempts to `insert` a row into `idempotency_keys` for
   `(user_id, key, operation)`.
2. If that insert hits the table's `unique_violation` (a concurrent or
   retried call with the same key), the function returns the **previously
   recorded result** instead of moving credits again.
3. Otherwise it performs the credit mutation, then updates that same
   `idempotency_keys` row with the outcome.

The natural idempotency key for a generation's charge is the generation's
own already-unique `generationId` — no new client-side token generation was
needed. Refunds use `` refund:<generationId> ``, monthly grants use
`` monthly:<userId>:<periodStartDate> ``.

## SQL functions (all `SECURITY DEFINER`, all `revoke execute` from
`public`/`anon`/`authenticated`)

These are **backend-only** — a client calling `supabase.rpc(...)` against
any of them directly is refused by Postgres before the function body even
runs (mirrors the existing `handle_new_user()` hardening from Phase 1's
`security_hardening.sql`). Only the four `generate-*` Edge Functions and
`video-status` (using their service-role key) can call them.

- **`reserve_credits(user_id, amount, idempotency_key, generation_id, ...)`**
  — the atomic charge described above. Returns
  `{success, code, error, transactionId, balanceAfter}`.
- **`finalize_generation_charge(generation_id, metadata)`** — marks the
  `usage_records` row `completed`. Moves no credits (the charge already
  happened in `reserve_credits`); naturally idempotent (repeat calls just
  re-set the same status).
- **`refund_generation_credits(user_id, amount, idempotency_key, generation_id, ...)`**
  — atomically restores the balance. Idempotent via its own idempotency key,
  **and** additionally guarded by only updating a `usage_records` row still
  in `processing`/`failed` — a row already `refunded` cannot be refunded
  again even if called with a different key by mistake.
- **`mark_generation_failed(generation_id, error_message)`** — marks
  `usage_records`/the reservation `failed` without moving credits, for the
  ambiguous-outcome case described below.
- **`grant_monthly_credits(user_id)`** — resets `credits_used` to 0 and sets
  `credits_limit` to the user's current plan's `monthly_credits`, guarded by
  (a) an early `NOT_DUE_YET` check against `current_period_end` (safe to call
  opportunistically/repeatedly) and (b) the standard idempotency mechanism
  keyed to the specific period.
- **`get_credit_cost(generation_type, variant)`** — the one exception: this
  is `SECURITY INVOKER` (not `DEFINER`), added in a follow-up migration
  (`20250101070100_credit_cost_function_hardening.sql`) after the Supabase
  security advisor flagged the original `DEFINER` version as
  over-privileged for a function that only reads an already
  publicly-readable table. RLS applies based on the actual caller, which is
  correct here since `credit_costs` has no sensitive rows.

## Edge Function integration

All four `generate-*` functions (`generate-image`, `generate-music`,
`generate-video`, `generate-funnel`) now follow the same billing lifecycle:

1. Verify the `generationId` in the request body is an existing
   `generations` row **owned by the caller** (via the user-scoped, RLS'd
   client) and of the matching type — a `generationId` alone is never
   treated as authorization.
2. Look up the current cost from `credit_costs` (server-side; the client
   never supplies or influences the amount actually charged).
3. Call `reserve_credits` **before** calling the AI provider. If it fails
   (`INSUFFICIENT_CREDITS`, `DUPLICATE_REQUEST`, ...), return that error
   immediately without ever calling the provider.
4. On any definitive failure after that point (provider error, invalid AI
   response, storage/database failure), call `refund_generation_credits`
   before returning the error.
5. On success, call `finalize_generation_charge`.

**Video is the one asymmetric case**: `generate-video` only *starts* an
async provider job, so it reserves credits at job-creation time and leaves
them charged while the job runs. `video-status` (polled by the client) is
where the job's eventual outcome is known, so it now:
 - calls `finalize_generation_charge` when the provider reports `completed`;
 - calls `refund_generation_credits` when the provider reports `failed`
   (looking up the original `GENERATION_CHARGE` transaction's amount so the
   refund is exact).

This closed a real pre-existing gap: before Phase 6, a video job that
failed after being charged was **never refunded** — `video-status` had zero
credit-handling code.

**Ambiguous states are deliberately left charged, not auto-refunded** — the
brief is explicit about this. If the client's poll loop simply times out
without the provider ever reporting a definitive `completed`/`failed`, no
code path here refunds that charge; only a definitive provider answer
(`completed` or `failed`) moves credits again. This avoids the failure mode
where a slow-but-eventually-successful job gets refunded out from under a
job that then completes.

## Flutter (client) changes

- `AppException` gained an optional `code` field carrying the backend's
  machine-readable error code (e.g. `INSUFFICIENT_CREDITS`) end-to-end: each
  `EdgeFunction*Provider` extracts it from the Edge Function's JSON error
  body, `GenerationOrchestrator` forwards it when re-wrapping a provider
  error, and each generator screen branches on it to show a dedicated
  "Not enough credits — View plans" dialog instead of a generic snackbar.
- `CreditSummary` gained `planCode`, `currentPeriodStart/End`,
  `cancelAtPeriodEnd`, `lifetimeCreditsEarned/Used` — every existing field
  and its JSON key are unchanged.
- New models: `Plan`, `CreditCost`, `CreditTransaction`, `UsageRecord` — all
  thin, RLS-respecting reads via `SupabaseCreditsRepository`.
- New screens: **Plan/Subscription** (`/plans` — Free/Pro/Business
  comparison, current-plan indicator, explicit "payment integration coming
  soon" messaging, no fake successful upgrade), **Usage Dashboard**
  (`/usage` — balance, renewal date, lifetime totals, per-type usage
  breakdown), **Credit History** (`/credits/history` — paginated ledger,
  "load more" on scroll).
- Every generator screen (`Image`/`Music`/`Video`/`Funnel`) now shows the
  live per-generation cost (from `credit_costs`, never hardcoded) next to
  its Generate button — **display only**; the backend independently
  recomputes and enforces the real cost, so a stale or missing value here
  can never let a generation through for the wrong price.
- `CreateGenerationController.submit()` now invalidates
  `creditSummaryProvider` on both success and failure, so the balance shown
  on Home/Profile/generator screens updates immediately without an app
  restart.
- The four `EdgeFunction*Provider`s now send `generationId` in every request
  body (previously only the funnel provider did, from Phase 5) — required
  by the now-billing-aware Edge Functions.
- `lib/features/credits/services/subscription_provider.dart`: an
  **unimplemented** `SubscriptionProvider` interface
  (`createCheckout`/`getSubscription`/`cancelSubscription`/
  `restoreSubscription`/`handleWebhook`) for a future real payment
  integration to implement — mirrors the existing `AIProvider` pattern.
  No concrete implementation exists; none should be added until real
  payment processing is explicitly scoped.

## Verification performed

- **Live SQL verification** against the deployed database (a throwaway test
  user, fully cleaned up afterward): `handle_new_user()` correctly grants
  the Free plan's credits from `plans` and records an initial
  `SUBSCRIPTION_GRANT`; `reserve_credits` charges correctly, is idempotent
  on retry (same key → cached result, no double charge), and rejects
  insufficient-credit requests without mutating the balance;
  `refund_generation_credits` restores the balance correctly and is blocked
  from double-refunding the same generation even with a different
  idempotency key; `grant_monthly_credits`'s `NOT_DUE_YET` gate, grant
  behavior, lifetime tracking, and double-grant prevention.
- **Flutter unit/widget tests** (`flutter test`, 187 passing, 0 analyzer
  issues): model parsing (`CreditSummary`, `Plan`, `CreditCost`,
  `CreditTransaction`, `UsageRecord`), `CreditHistoryController`'s
  load-more/hasMore/refresh paging logic, `AppException.code` propagation
  from a provider error through `GenerationOrchestrator` to the final
  `Result.failure`, and each `EdgeFunction*Provider`'s `generationId`
  forwarding and `INSUFFICIENT_CREDITS` code mapping.
- **Supabase security advisor**: no new findings beyond the pre-existing,
  intentional `idempotency_keys` INFO finding (RLS enabled, zero policies —
  by design). The `auth_rls_initplan` performance WARN affects every table
  in the project (a pre-existing pattern from Phase 1 onward); Phase 6's new
  policies follow that same established pattern for consistency and were
  not treated as an in-scope fix.
- `flutter build apk --debug` succeeds.

## What Phase 6 deliberately does NOT do

- No real payment processing, no payment provider SDK/credentials anywhere
  in the codebase.
- No simulated/fake successful payment of any kind.
- No final, hardcoded pricing — `plans.price_display` is placeholder text.
- No changes to Phase 1-5 features beyond what billing integration required
  (adding `generationId` to request bodies, adding credit calls around the
  existing provider-call logic).
