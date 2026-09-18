import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/features/credits/data/models/credit_cost.dart';
import 'package:createai_studio/features/credits/data/models/credit_summary.dart';
import 'package:createai_studio/features/credits/data/models/credit_transaction.dart';
import 'package:createai_studio/features/credits/data/models/plan.dart';
import 'package:createai_studio/features/credits/data/models/usage_record.dart';

void main() {
  group('CreditSummary', () {
    test('fromJson parses the Phase 6 fields alongside the original ones', () {
      final summary = CreditSummary.fromJson({
        'plan_name': 'pro',
        'credits_limit': 500,
        'credits_used': 120,
        'current_period_start': '2025-01-01T00:00:00.000Z',
        'current_period_end': '2025-02-01T00:00:00.000Z',
        'cancel_at_period_end': true,
        'lifetime_credits_earned': 1500,
        'lifetime_credits_used': 900,
      });

      expect(summary.planName, 'pro');
      expect(summary.planCode, 'pro');
      expect(summary.creditsLimit, 500);
      expect(summary.creditsUsed, 120);
      expect(summary.creditsRemaining, 380);
      expect(summary.currentPeriodEnd, DateTime.parse('2025-02-01T00:00:00.000Z'));
      expect(summary.cancelAtPeriodEnd, isTrue);
      expect(summary.lifetimeCreditsEarned, 1500);
      expect(summary.lifetimeCreditsUsed, 900);
    });

    test('fromJson falls back to Free defaults when fields are missing', () {
      final summary = CreditSummary.fromJson(const {});

      expect(summary.planName, 'Free');
      expect(summary.creditsLimit, 50);
      expect(summary.creditsUsed, 0);
      expect(summary.currentPeriodEnd, isNull);
      expect(summary.cancelAtPeriodEnd, isFalse);
    });

    test('creditsRemaining never goes negative even if used exceeds limit', () {
      const summary = CreditSummary(planName: 'Free', creditsLimit: 50, creditsUsed: 999);
      expect(summary.creditsRemaining, 0);
    });
  });

  group('Plan', () {
    test('fromJson parses a plans row', () {
      final plan = Plan.fromJson({
        'code': 'business',
        'name': 'Business',
        'description': 'The most credits, for teams.',
        'monthly_credits': 2000,
        'price_display': 'Pricing coming soon',
        'active': true,
        'features': {'priority_support': true, 'team_seats': true},
      });

      expect(plan.code, 'business');
      expect(plan.name, 'Business');
      expect(plan.monthlyCredits, 2000);
      expect(plan.priceDisplay, 'Pricing coming soon');
      expect(plan.features['team_seats'], isTrue);
    });
  });

  group('CreditCost', () {
    test('fromJson parses a credit_costs row', () {
      final cost = CreditCost.fromJson({
        'generation_type': 'video',
        'variant': null,
        'cost': 5,
        'active': true,
      });

      expect(cost.generationType, 'video');
      expect(cost.variant, isNull);
      expect(cost.cost, 5);
      expect(cost.active, isTrue);
    });
  });

  group('CreditTransaction', () {
    test('fromJson parses a credit_transactions row and isCredit reflects sign', () {
      final charge = CreditTransaction.fromJson({
        'id': 'tx-1',
        'amount': -5,
        'transaction_type': 'GENERATION_CHARGE',
        'description': 'Video generation',
        'reference_id': 'gen-1',
        'reference_type': 'generation',
        'balance_after': 45,
        'created_at': '2025-01-05T10:00:00.000Z',
      });

      expect(charge.isCredit, isFalse);
      expect(charge.amount, -5);
      expect(charge.balanceAfter, 45);

      final grant = CreditTransaction.fromJson({
        'id': 'tx-2',
        'amount': 50,
        'transaction_type': 'MONTHLY_GRANT',
        'created_at': '2025-01-01T00:00:00.000Z',
      });

      expect(grant.isCredit, isTrue);
    });
  });

  group('UsageRecord', () {
    test('fromJson parses a usage_records row', () {
      final record = UsageRecord.fromJson({
        'id': 'usage-1',
        'generation_type': 'image',
        'credits_consumed': 2,
        'status': 'completed',
        'created_at': '2025-01-05T10:00:00.000Z',
      });

      expect(record.generationType, 'image');
      expect(record.creditsConsumed, 2);
      expect(record.status, 'completed');
    });
  });
}
