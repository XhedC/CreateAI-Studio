import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_lead_model.dart';
import 'package:createai_studio/features/funnel_generation/data/repositories/funnel_leads_repository.dart';
import 'package:createai_studio/features/funnel_generation/presentation/providers/funnel_providers.dart';

class _FakeFunnelLeadsRepository implements FunnelLeadsRepository {
  bool shouldFail = false;
  String failureMessage = 'This submission could not be processed.';
  int submitCallCount = 0;
  Map<String, dynamic>? lastSubmission;

  @override
  Future<Result<void>> submitPublicLead({
    required String slug,
    String? name,
    String? email,
    String? phone,
    String? message,
  }) async {
    submitCallCount++;
    lastSubmission = {'slug': slug, 'email': email, 'phone': phone};
    if (shouldFail) {
      return Result.failure(ValidationException(failureMessage));
    }
    return const Result.success(null);
  }

  @override
  Future<Result<FunnelLeadModel>> submitLead({
    required String funnelId,
    required String userId,
    String? name,
    String? email,
    String? phone,
    String? message,
  }) =>
      throw UnimplementedError();
  @override
  Future<Result<List<FunnelLeadModel>>> getLeads(String funnelId) => throw UnimplementedError();
  @override
  Future<Result<void>> deleteLead(String id) => throw UnimplementedError();
}

void main() {
  late _FakeFunnelLeadsRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeFunnelLeadsRepository();
    container = ProviderContainer(overrides: [
      funnelLeadsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
  });

  test('submit() requires an email or phone number, and never calls the repository without one', () async {
    final controller = container.read(publicLeadFormControllerProvider.notifier);

    final ok = await controller.submit(slug: 'test-funnel', name: 'Jane');

    expect(ok, isFalse);
    expect(repo.submitCallCount, 0);
    expect(
      container.read(publicLeadFormControllerProvider).errorMessage,
      'Please provide an email or phone number.',
    );
  });

  test('submit() succeeds and moves to the success state', () async {
    final controller = container.read(publicLeadFormControllerProvider.notifier);

    final ok = await controller.submit(slug: 'test-funnel', email: 'visitor@example.com');

    expect(ok, isTrue);
    expect(repo.lastSubmission?['slug'], 'test-funnel');
    expect(container.read(publicLeadFormControllerProvider).status, LeadFormStatus.success);
  });

  test('submit() surfaces the backend validation message on failure', () async {
    repo.shouldFail = true;
    repo.failureMessage = 'Please enter a valid email address.';
    final controller = container.read(publicLeadFormControllerProvider.notifier);

    final ok = await controller.submit(slug: 'test-funnel', email: 'not-an-email');

    expect(ok, isFalse);
    expect(container.read(publicLeadFormControllerProvider).status, LeadFormStatus.error);
    expect(
      container.read(publicLeadFormControllerProvider).errorMessage,
      'Please enter a valid email address.',
    );
  });

  test('submit() is a no-op while a submission is already in flight, preventing a double-submit', () async {
    final controller = container.read(publicLeadFormControllerProvider.notifier);

    final first = controller.submit(slug: 'test-funnel', email: 'visitor@example.com');
    // Fired immediately, before the first submission resolves - simulates a
    // fast double-tap on the submit button.
    final second = await controller.submit(slug: 'test-funnel', email: 'visitor@example.com');
    await first;

    expect(second, isFalse);
    expect(repo.submitCallCount, 1);
  });

  test('reset() returns the form to its initial state after a success', () async {
    final controller = container.read(publicLeadFormControllerProvider.notifier);
    await controller.submit(slug: 'test-funnel', email: 'visitor@example.com');

    controller.reset();

    expect(container.read(publicLeadFormControllerProvider).status, LeadFormStatus.initial);
  });
}
