import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/errors/app_exception.dart';
import 'package:createai_studio/core/utils/result.dart';
import 'package:createai_studio/features/auth/data/models/app_user.dart';
import 'package:createai_studio/features/auth/data/repositories/auth_repository.dart';
import 'package:createai_studio/features/auth/presentation/providers/auth_providers.dart';
import 'package:createai_studio/features/funnel_generation/data/models/funnel_lead_model.dart';
import 'package:createai_studio/features/funnel_generation/data/repositories/funnel_leads_repository.dart';
import 'package:createai_studio/features/funnel_generation/presentation/providers/funnel_providers.dart';
import 'package:createai_studio/features/funnel_generation/presentation/widgets/lead_form_widget.dart';

class _FakeAuthRepository implements AuthRepository {
  final _user = const AppUser(id: 'user-1', email: 'user@example.com');
  @override
  AppUser? get currentUser => _user;
  @override
  Stream<AppUser?> get authStateChanges => Stream.value(_user);
  @override
  Future<Result<AppUser>> signIn({required String email, required String password}) async =>
      Result.success(_user);
  @override
  Future<Result<AppUser>> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async =>
      Result.success(_user);
  @override
  Future<Result<void>> signOut() async => const Result.success(null);
  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async => const Result.success(null);
}

class _FakeFunnelLeadsRepository implements FunnelLeadsRepository {
  bool shouldFail = false;
  Map<String, dynamic>? lastSubmission;

  @override
  Future<Result<FunnelLeadModel>> submitLead({
    required String funnelId,
    required String userId,
    String? name,
    String? email,
    String? phone,
    String? message,
  }) async {
    lastSubmission = {'funnelId': funnelId, 'email': email, 'phone': phone};
    if (shouldFail) {
      return const Result.failure(GenerationException(message: 'Could not submit your request.'));
    }
    return Result.success(FunnelLeadModel(
      id: 'lead-1',
      funnelId: funnelId,
      userId: userId,
      name: name,
      email: email,
      phone: phone,
      message: message,
      createdAt: DateTime(2025, 1, 1),
    ));
  }

  @override
  Future<Result<List<FunnelLeadModel>>> getLeads(String funnelId) async => const Result.success([]);
  @override
  Future<Result<void>> deleteLead(String id) async => const Result.success(null);
}

Future<_FakeFunnelLeadsRepository> _pumpForm(WidgetTester tester) async {
  final repo = _FakeFunnelLeadsRepository();
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        funnelLeadsRepositoryProvider.overrideWithValue(repo),
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const MaterialApp(
            home: Scaffold(body: LeadFormWidget(funnelId: 'funnel-1')),
          );
        },
      ),
    ),
  );
  // authStateProvider is a StreamProvider - in the real app it's always kept
  // alive by an ambient watcher (the router's redirect logic, Home screen),
  // so a plain ref.read() inside a submit handler reliably sees its current
  // value. A bare container.read() with no listener does NOT keep a
  // StreamProvider's subscription alive between reads in Riverpod 3 - it
  // gets torn down immediately, so .value would stay null forever. A
  // persistent container.listen() (never cancelled - the container itself
  // is torn down when the test ends) reproduces the app's real warm-keeping
  // behavior here.
  container.listen(authStateProvider, (previous, next) {});
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('renders Name/Email/Phone/Message fields and a Submit button', (tester) async {
    await _pumpForm(tester);

    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Phone'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Message (optional)'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
  });

  testWidgets('shows a validation error when neither email nor phone is provided', (tester) async {
    await _pumpForm(tester);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Please provide an email or phone number.'), findsWidgets);
  });

  testWidgets('submits and shows the success state', (tester) async {
    final repo = await _pumpForm(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'lead@example.com');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(repo.lastSubmission?['email'], 'lead@example.com');
    expect(find.textContaining("Thank you"), findsOneWidget);
  });

  testWidgets('shows the error message when submission fails', (tester) async {
    final repo = await _pumpForm(tester);
    repo.shouldFail = true;

    await tester.enterText(find.widgetWithText(TextFormField, 'Phone'), '555-1234');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Could not submit your request.'), findsOneWidget);
  });
}
