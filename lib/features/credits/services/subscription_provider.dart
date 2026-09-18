// The future payment-provider integration point for Phase 6's billing
// foundation - deliberately UNIMPLEMENTED in this phase. See
// docs/PHASE_6_CREDITS_SUBSCRIPTIONS.md.
//
// Mirrors lib/features/generation/services/ai_provider.dart's shape: the
// app (and, eventually, a Checkout screen) would only ever depend on this
// interface, so wiring in a real vendor (Stripe, Google Play Billing, Apple
// In-App Purchase, ...) later is a matter of adding one implementation
// class here plus registering it in a provider - no other code should need
// to change. `billing_events` (see the Phase 6 migration) already exists to
// log whatever a real implementation's webhook/callback receives, but
// nothing writes to it yet because no real provider exists yet.
//
// No concrete implementation of this interface exists anywhere in this
// codebase, and none should be added until real payment processing is
// explicitly requested and scoped - per the Phase 6 brief, this phase ships
// the architecture only, never a fake or simulated successful payment.

/// One subscription-provider-neutral checkout request. `planCode` must be
/// one of the DB-driven `plans.code` values (never a hardcoded plan name).
class CheckoutRequest {
  const CheckoutRequest({
    required this.userId,
    required this.planCode,
    this.successUrl,
    this.cancelUrl,
  });

  final String userId;
  final String planCode;
  final String? successUrl;
  final String? cancelUrl;
}

/// Where a checkout flow sends the user next (e.g. a hosted payment page
/// URL, or a native purchase flow token) - shape intentionally vague since
/// it depends entirely on which real provider is eventually wired in.
class CheckoutSession {
  const CheckoutSession({required this.sessionId, this.redirectUrl});

  final String sessionId;
  final String? redirectUrl;
}

/// A provider-neutral view of subscription state, distinct from the app's
/// own `subscriptions` table row - a real implementation would reconcile
/// the two, not replace one with the other.
class ProviderSubscriptionStatus {
  const ProviderSubscriptionStatus({
    required this.providerSubscriptionId,
    required this.status,
    this.currentPeriodEnd,
  });

  final String providerSubscriptionId;
  final String status;
  final DateTime? currentPeriodEnd;
}

/// The contract any future payment provider integration must implement.
/// Every method is a no-op contract today - see the file header. A
/// concrete implementation must NEVER fabricate a successful result; if it
/// cannot reach the real provider, it must throw or return a failure, the
/// same way [AIProvider] implementations do.
abstract class SubscriptionProvider {
  /// Starts a checkout flow for the given plan. Returns where to send the
  /// user next; does not itself grant any credits or change
  /// `subscriptions` - only a confirmed webhook/callback (see
  /// [handleWebhook]) may ever do that, server-side.
  Future<CheckoutSession> createCheckout(CheckoutRequest request);

  /// Reads the current subscription state directly from the provider (not
  /// from this app's own `subscriptions` table), for reconciliation.
  Future<ProviderSubscriptionStatus?> getSubscription(String providerSubscriptionId);

  /// Requests cancellation (typically at period end) via the provider.
  Future<void> cancelSubscription(String providerSubscriptionId);

  /// Re-activates a subscription previously marked to cancel at period end.
  Future<void> restoreSubscription(String providerSubscriptionId);

  /// Verifies and processes one incoming provider webhook/callback event.
  /// A real implementation must verify the event's signature before acting
  /// on it, and should record it in `billing_events` before applying any
  /// resulting credit/subscription change - never trust a webhook payload
  /// blindly. Implemented server-side (an Edge Function), never in Flutter,
  /// since it must run without a signed-in user's session.
  Future<void> handleWebhook(Map<String, dynamic> payload, {required String signature});
}
