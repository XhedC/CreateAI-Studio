import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../generation/presentation/providers/generation_providers.dart';
import '../../../image_generation/data/models/reference_image.dart';
import '../../../image_generation/presentation/providers/image_generation_providers.dart'
    show ReferenceImageNotifier;
import '../../data/models/funnel_lead_model.dart';
import '../../data/models/funnel_model.dart';
import '../../data/models/funnel_schema.dart';
import '../../data/repositories/funnel_leads_repository.dart';
import '../../data/repositories/funnel_repository.dart';

final funnelRepositoryProvider = Provider<FunnelRepository>((ref) {
  return SupabaseFunnelRepository(ref.watch(supabaseClientProvider));
});

final funnelLeadsRepositoryProvider = Provider<FunnelLeadsRepository>((ref) {
  return SupabaseFunnelLeadsRepository(ref.watch(supabaseClientProvider));
});

/// A funnel looked up by the `generations` row that created it - what the
/// generic [GenerationDetailScreen] uses to offer "Open Editor"/"Preview"
/// for a funnel-type generation.
final funnelByGenerationIdProvider =
    FutureProvider.autoDispose.family<FunnelModel?, String>((ref, generationId) async {
  final result = await ref.read(funnelRepositoryProvider).getFunnelByGenerationId(generationId);
  return result.when(success: (f) => f, failure: (_) => null);
});

final funnelByIdProvider =
    FutureProvider.autoDispose.family<FunnelModel?, String>((ref, id) async {
  final result = await ref.read(funnelRepositoryProvider).getFunnel(id);
  return result.when(success: (f) => f, failure: (_) => null);
});

// --- Funnel Generator screen selection state -------------------------------

class FunnelSelection extends Equatable {
  const FunnelSelection({this.funnelType = FunnelType.custom, this.goal = FunnelGoal.custom});

  final FunnelType funnelType;
  final FunnelGoal goal;

  FunnelSelection copyWith({FunnelType? funnelType, FunnelGoal? goal}) => FunnelSelection(
        funnelType: funnelType ?? this.funnelType,
        goal: goal ?? this.goal,
      );

  @override
  List<Object?> get props => [funnelType, goal];
}

class FunnelSelectionNotifier extends Notifier<FunnelSelection> {
  @override
  FunnelSelection build() => const FunnelSelection();

  void setFunnelType(FunnelType value) => state = state.copyWith(funnelType: value);
  void setGoal(FunnelGoal value) => state = state.copyWith(goal: value);
  void reset() => state = const FunnelSelection();
}

final funnelSelectionProvider =
    NotifierProvider<FunnelSelectionNotifier, FunnelSelection>(FunnelSelectionNotifier.new);

/// A funnel needs two INDEPENDENT optional images (logo, product/reference)
/// at once, unlike image/video's single reference image slot - so rather
/// than reuse image_generation's single `referenceImageProvider`, this
/// declares two instances of the same reusable [ReferenceImageNotifier].
final funnelLogoImageProvider =
    NotifierProvider<ReferenceImageNotifier, ReferenceImage?>(ReferenceImageNotifier.new);
final funnelProductImageProvider =
    NotifierProvider<ReferenceImageNotifier, ReferenceImage?>(ReferenceImageNotifier.new);

// --- Funnel Editor -----------------------------------------------------

/// Loads one funnel and lets the Funnel Editor screen make in-memory edits
/// (section content, visibility, order, theme, SEO) before persisting them
/// with [save]. Every mutation re-validates through
/// [FunnelSchemaValidator.validate] indirectly via [FunnelSchema] staying a
/// well-typed object end to end - there is no path from raw, unvalidated
/// JSON into this controller's state.
class FunnelEditorController extends AsyncNotifier<FunnelModel> {
  FunnelEditorController(this.funnelId);

  final String funnelId;

  @override
  Future<FunnelModel> build() async {
    final result = await ref.read(funnelRepositoryProvider).getFunnel(funnelId);
    return result.when(success: (f) => f, failure: (e) => throw e);
  }

  FunnelModel? get _current => state.value;

  void _updateContent(FunnelSchema Function(FunnelSchema) transform) {
    final current = _current;
    if (current == null) return;
    state = AsyncData(current.copyWith(content: transform(current.content)));
  }

  void updateName(String name) {
    _updateContent((c) => c.copyWith(name: name));
  }

  void updateSeo({String? title, String? description}) {
    _updateContent((c) => c.copyWith(
          seo: c.seo.copyWith(title: title, description: description),
        ));
  }

  void updateTheme({String? primaryColor, String? secondaryColor}) {
    _updateContent((c) => c.copyWith(
          theme: c.theme.copyWith(primaryColor: primaryColor, secondaryColor: secondaryColor),
        ));
  }

  /// Replaces one section's content map (e.g. headline/subheadline/cta text
  /// fields edited in the Section Editor) - shallow-merges [changes] into
  /// the existing content so a partial edit never drops unrelated keys.
  void updateSectionContent(String sectionId, Map<String, dynamic> changes) {
    _updateContent((c) => c.copyWith(
          sections: [
            for (final s in c.sections)
              if (s.id == sectionId) s.copyWith(content: {...s.content, ...changes}) else s,
          ],
        ));
  }

  void setSectionVisible(String sectionId, bool visible) {
    _updateContent((c) => c.copyWith(
          sections: [
            for (final s in c.sections)
              if (s.id == sectionId) s.copyWith(visible: visible) else s,
          ],
        ));
  }

  void removeSection(String sectionId) {
    _updateContent((c) => c.copyWith(
          sections: c.sections.where((s) => s.id != sectionId).toList(),
        ));
  }

  void addSection(FunnelSectionType type) {
    _updateContent((c) {
      final id = '${type.value}-${DateTime.now().millisecondsSinceEpoch}';
      return c.copyWith(sections: [...c.sections, _defaultSection(id, type)]);
    });
  }

  /// Simple, dependable reordering per the brief's fallback
  /// ("Move Up"/"Move Down" first, drag-and-drop later without an
  /// architecture change since sections are already a plain ordered list).
  void moveSectionUp(String sectionId) => _moveSection(sectionId, -1);
  void moveSectionDown(String sectionId) => _moveSection(sectionId, 1);

  void _moveSection(String sectionId, int delta) {
    final current = _current;
    if (current == null) return;
    final sections = [...current.content.sections];
    final index = sections.indexWhere((s) => s.id == sectionId);
    final target = index + delta;
    if (index == -1 || target < 0 || target >= sections.length) return;
    final section = sections.removeAt(index);
    sections.insert(target, section);
    _updateContent((c) => c.copyWith(sections: sections));
  }

  /// Full reorder for a drag-and-drop `ReorderableListView` - the
  /// architecture (a plain ordered `List<FunnelSection>`) already supports
  /// this; `oldIndex`/`newIndex` are exactly what `onReorder` provides.
  void reorderSections(int oldIndex, int newIndex) {
    final current = _current;
    if (current == null) return;
    final sections = [...current.content.sections];
    if (newIndex > oldIndex) newIndex -= 1;
    final section = sections.removeAt(oldIndex);
    sections.insert(newIndex, section);
    _updateContent((c) => c.copyWith(sections: sections));
  }

  FunnelSection _defaultSection(String id, FunnelSectionType type) {
    switch (type) {
      case FunnelSectionType.hero:
        return FunnelSection(id: id, type: type.value, content: const {
          'headline': 'Your headline here',
          'subheadline': 'Your subheadline here',
          'cta': 'Get Started',
        });
      case FunnelSectionType.faq:
        return FunnelSection(id: id, type: type.value, content: const {
          'title': 'Frequently asked questions',
          'items': [
            {'question': 'A question', 'answer': 'Its answer'},
          ],
        });
      case FunnelSectionType.testimonials:
        return FunnelSection(id: id, type: type.value, content: const {
          'title': 'What our customers say',
          'items': [
            {'quote': 'Placeholder testimonial.', 'author': 'Placeholder'},
          ],
        });
      case FunnelSectionType.leadForm:
        return FunnelSection(id: id, type: type.value, content: const {
          'title': 'Request more information',
          'submitLabel': 'Submit',
        });
      default:
        return FunnelSection(id: id, type: type.value, content: {'title': type.label});
    }
  }

  Future<bool> save() async {
    final current = _current;
    if (current == null) return false;
    final result = await ref.read(funnelRepositoryProvider).updateFunnel(
          funnelId,
          name: current.content.name,
          content: current.content,
        );
    return result.when(
      success: (updated) {
        state = AsyncData(updated);
        ref.invalidate(funnelByGenerationIdProvider(updated.generationId));
        ref.invalidate(funnelByIdProvider(updated.id));
        return true;
      },
      failure: (_) => false,
    );
  }
}

final funnelEditorProvider =
    AsyncNotifierProvider.autoDispose.family<FunnelEditorController, FunnelModel, String>(
  FunnelEditorController.new,
);

// --- Duplicate -----------------------------------------------------------

/// "Duplicate Funnel": creates a brand-new `generations` row (completed
/// immediately - no AI call, no credit cost, since nothing was generated)
/// and a brand-new `funnels` row copying the original's content, leaving
/// the original completely untouched. See docs/funnel-generation.md.
class FunnelDuplicateController extends AsyncNotifier<FunnelModel?> {
  @override
  Future<FunnelModel?> build() async => null;

  Future<bool> duplicate(FunnelModel original) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return false;
    state = const AsyncLoading();

    final genRepo = ref.read(generationRepositoryProvider);
    final funnelRepo = ref.read(funnelRepositoryProvider);
    final newName = 'Copy of ${original.name}';

    final createResult = await genRepo.createGeneration(
      userId: user.id,
      projectId: original.projectId,
      generationType: 'funnel',
      prompt: newName,
    );

    return createResult.when(
      success: (generation) async {
        final newContent = original.content.copyWith(name: newName);
        final insertResult = await funnelRepo.insertFunnel(
          userId: user.id,
          projectId: original.projectId,
          generationId: generation.id,
          name: newName,
          description: original.description,
          funnelType: original.funnelType,
          content: newContent,
        );
        return insertResult.when(
          success: (newFunnel) async {
            await genRepo.updateGeneration(
              generation.id,
              status: 'completed',
              resultText: newName,
              metadata: {'funnelId': newFunnel.id, 'funnelType': newFunnel.funnelType},
              completedAt: DateTime.now(),
            );
            state = AsyncData(newFunnel);
            ref.invalidate(generationsProvider);
            ref.invalidate(recentGenerationsProvider);
            return true;
          },
          failure: (error) {
            state = AsyncError(error, StackTrace.current);
            return false;
          },
        );
      },
      failure: (error) async {
        state = AsyncError(error, StackTrace.current);
        return false;
      },
    );
  }
}

final funnelDuplicateControllerProvider =
    AsyncNotifierProvider<FunnelDuplicateController, FunnelModel?>(FunnelDuplicateController.new);

// --- Lead Form -------------------------------------------------------------

enum LeadFormStatus { initial, validating, submitting, success, error }

class LeadFormState extends Equatable {
  const LeadFormState({this.status = LeadFormStatus.initial, this.errorMessage});

  final LeadFormStatus status;
  final String? errorMessage;

  LeadFormState copyWith({LeadFormStatus? status, String? errorMessage}) => LeadFormState(
        status: status ?? this.status,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [status, errorMessage];
}

class LeadFormController extends Notifier<LeadFormState> {
  @override
  LeadFormState build() => const LeadFormState();

  Future<bool> submit({
    required String funnelId,
    String? name,
    String? email,
    String? phone,
    String? message,
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      state = const LeadFormState(
        status: LeadFormStatus.error,
        errorMessage: 'You must be signed in to submit this form.',
      );
      return false;
    }
    if ((email == null || email.trim().isEmpty) && (phone == null || phone.trim().isEmpty)) {
      state = const LeadFormState(
        status: LeadFormStatus.error,
        errorMessage: 'Please provide an email or phone number.',
      );
      return false;
    }

    state = const LeadFormState(status: LeadFormStatus.submitting);
    final result = await ref.read(funnelLeadsRepositoryProvider).submitLead(
          funnelId: funnelId,
          userId: user.id,
          name: name,
          email: email,
          phone: phone,
          message: message,
        );
    return result.when(
      success: (_) {
        state = const LeadFormState(status: LeadFormStatus.success);
        return true;
      },
      failure: (error) {
        state = LeadFormState(status: LeadFormStatus.error, errorMessage: error.message);
        return false;
      },
    );
  }

  void reset() => state = const LeadFormState();
}

final leadFormControllerProvider =
    NotifierProvider.autoDispose<LeadFormController, LeadFormState>(LeadFormController.new);

/// Every lead captured by one funnel - used by a future "View leads" screen;
/// not required for Phase 5's acceptance criteria but wired up now since the
/// repository already exists.
final funnelLeadsProvider =
    FutureProvider.autoDispose.family<List<FunnelLeadModel>, String>((ref, funnelId) async {
  final result = await ref.read(funnelLeadsRepositoryProvider).getLeads(funnelId);
  return result.when(success: (leads) => leads, failure: (_) => []);
});
