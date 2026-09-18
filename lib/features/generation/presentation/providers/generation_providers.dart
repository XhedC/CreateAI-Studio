import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../credits/presentation/providers/credits_providers.dart';
import '../../data/models/generation_file_model.dart';
import '../../data/models/generation_model.dart';
import '../../data/repositories/generation_repository.dart';
import '../../services/ai_provider.dart';
import '../../services/edge_function_funnel_provider.dart';
import '../../services/edge_function_image_provider.dart';
import '../../services/edge_function_music_provider.dart';
import '../../services/edge_function_video_provider.dart';
import '../../services/file_upload_service.dart';
import '../../services/funnel_generation_service.dart';
import '../../services/generation_orchestrator.dart';
import '../../services/image_generation_service.dart';
import '../../services/mock_ai_provider.dart';
import '../../services/music_generation_service.dart';
import '../../services/text_generation_service.dart';
import '../../services/video_generation_service.dart';

final generationRepositoryProvider = Provider<GenerationRepository>((ref) {
  return SupabaseGenerationRepository(ref.watch(supabaseClientProvider));
});

/// Lets Home's "Quick Create" tiles preselect a category on the Create tab.
/// Set before switching tabs, read (and cleared) once by the Create screen.
class PendingCreationTypeNotifier extends Notifier<CreationType?> {
  @override
  CreationType? build() => null;

  void set(CreationType? type) => state = type;
}

final pendingCreationTypeProvider =
    NotifierProvider<PendingCreationTypeNotifier, CreationType?>(
  PendingCreationTypeNotifier.new,
);

final fileUploadServiceProvider = Provider<FileUploadService>((ref) {
  return FileUploadService(ref.watch(supabaseClientProvider));
});

// --- Provider wiring -------------------------------------------------------
// This is the one place that decides which concrete AIProvider backs each
// creation type. Phase 1 wires every type to its mock implementation; a real
// integration later replaces a single line here (e.g.
// `imageAIProviderProvider` returning `OpenAiImageProvider(...)`) with no
// changes anywhere else in the app.

final textAIProviderProvider = Provider<TextAIProvider>((ref) => MockTextAIProvider());
// Phase 2: Image generation now calls the real `generate-image` Edge
// Function instead of the Phase 1 mock. The Edge Function itself still
// defaults to a mock AI backend until AI_IMAGE_PROVIDER=openai (+ a key) is
// configured server-side - see docs/image-generation.md - so this is safe
// to leave wired even without real credentials.
final imageAIProviderProvider = Provider<ImageAIProvider>(
  (ref) => EdgeFunctionImageProvider(ref.watch(supabaseClientProvider)),
);
// Phase 3: Music generation now calls the real `generate-music` Edge
// Function - same pattern as Image above. It defaults to a mock backend
// until MUSIC_GENERATION_PROVIDER=stability (+ a key) is configured
// server-side - see docs/music-generation.md.
final musicAIProviderProvider = Provider<MusicAIProvider>(
  (ref) => EdgeFunctionMusicProvider(ref.watch(supabaseClientProvider)),
);
// Phase 4: Video generation now calls the real `generate-video` Edge
// Function - same pattern as Image/Music above, except genuinely async
// (see EdgeFunctionVideoProvider and docs/video-generation.md). Defaults to
// a mock backend until VIDEO_GENERATION_PROVIDER=stability (+ a key) is
// configured server-side.
final videoAIProviderProvider = Provider<VideoAIProvider>(
  (ref) => EdgeFunctionVideoProvider(ref.watch(supabaseClientProvider)),
);
// Phase 5: Funnel generation now calls the real `generate-funnel` Edge
// Function - same pattern as Image/Music above (single synchronous round
// trip). Defaults to a mock backend until FUNNEL_GENERATION_PROVIDER=openai
// (+ a key) is configured server-side - see docs/funnel-generation.md.
final funnelAIProviderProvider = Provider<FunnelAIProvider>(
  (ref) => EdgeFunctionFunnelProvider(ref.watch(supabaseClientProvider)),
);

final textGenerationServiceProvider = Provider<TextGenerationService>(
  (ref) => TextGenerationService(ref.watch(textAIProviderProvider)),
);
final imageGenerationServiceProvider = Provider<ImageGenerationService>(
  (ref) => ImageGenerationService(ref.watch(imageAIProviderProvider)),
);
final musicGenerationServiceProvider = Provider<MusicGenerationService>(
  (ref) => MusicGenerationService(ref.watch(musicAIProviderProvider)),
);
final videoGenerationServiceProvider = Provider<VideoGenerationService>(
  (ref) => VideoGenerationService(ref.watch(videoAIProviderProvider)),
);
final funnelGenerationServiceProvider = Provider<FunnelGenerationService>(
  (ref) => FunnelGenerationService(ref.watch(funnelAIProviderProvider)),
);

final generationOrchestratorProvider = Provider<GenerationOrchestrator>((ref) {
  return GenerationOrchestrator(
    repository: ref.watch(generationRepositoryProvider),
    networkService: ref.watch(networkServiceProvider),
    providersByType: {
      CreationType.text: ref.watch(textGenerationServiceProvider).provider,
      CreationType.image: ref.watch(imageGenerationServiceProvider).provider,
      CreationType.music: ref.watch(musicGenerationServiceProvider).provider,
      CreationType.video: ref.watch(videoGenerationServiceProvider).provider,
      CreationType.funnel: ref.watch(funnelGenerationServiceProvider).provider,
    },
  );
});

// --- History / listing -------------------------------------------------

class HistoryFilters {
  const HistoryFilters({this.type, this.searchQuery = ''});

  final CreationType? type;
  final String searchQuery;

  HistoryFilters copyWith({CreationType? type, bool clearType = false, String? searchQuery}) {
    return HistoryFilters(
      type: clearType ? null : (type ?? this.type),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class HistoryFiltersNotifier extends Notifier<HistoryFilters> {
  @override
  HistoryFilters build() => const HistoryFilters();

  void setType(CreationType? type) {
    state = state.copyWith(type: type, clearType: type == null);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

final historyFiltersProvider =
    NotifierProvider<HistoryFiltersNotifier, HistoryFilters>(
  HistoryFiltersNotifier.new,
);

/// All of the current user's generations, filtered by [historyFiltersProvider].
final generationsProvider = FutureProvider.autoDispose<List<GenerationModel>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final filters = ref.watch(historyFiltersProvider);
  final result = await ref.read(generationRepositoryProvider).getGenerations(
        user.id,
        generationType: filters.type?.value,
        searchQuery: filters.searchQuery,
      );
  return result.when(success: (data) => data, failure: (e) => throw e);
});

/// Generations that belong to a specific project (used by Project detail).
final generationsByProjectProvider =
    FutureProvider.autoDispose.family<List<GenerationModel>, String>((ref, projectId) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final result = await ref
      .read(generationRepositoryProvider)
      .getGenerations(user.id, projectId: projectId);
  return result.when(success: (data) => data, failure: (e) => throw e);
});

final generationByIdProvider =
    FutureProvider.autoDispose.family<GenerationModel?, String>((ref, id) async {
  final result = await ref.read(generationRepositoryProvider).getGeneration(id);
  return result.when(success: (g) => g, failure: (_) => null);
});

/// Extra output files beyond a generation's primary result (e.g. images 2-4
/// of a multi-image request) - see GenerationOrchestrator.additionalFiles.
final generationFilesProvider = FutureProvider.autoDispose
    .family<List<GenerationFileModel>, String>((ref, generationId) async {
  final result =
      await ref.read(generationRepositoryProvider).getFiles(generationId);
  return result.when(success: (files) => files, failure: (_) => []);
});

/// Recent generations for the Home dashboard (top 5), independent of any
/// active History filter/search.
final recentGenerationsProvider = FutureProvider.autoDispose<List<GenerationModel>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final result = await ref.read(generationRepositoryProvider).getGenerations(user.id);
  return result.when(
    success: (data) => data.take(5).toList(),
    failure: (e) => throw e,
  );
});

// --- Create flow ---------------------------------------------------------

/// Drives the Create screen's Generate button: submits a request through the
/// [GenerationOrchestrator], exposes loading/error via [AsyncValue], and
/// refreshes every list that could show the new generation.
class CreateGenerationController extends AsyncNotifier<GenerationModel?> {
  @override
  Future<GenerationModel?> build() async => null;

  Future<bool> submit({
    required CreationType type,
    required String prompt,
    String? projectId,
    List<String> attachmentUrls = const [],
    Map<String, dynamic> options = const {},
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return false;
    // Defense in depth beyond the Generate button's own disabled-while-
    // loading state: never let two submissions race even if both fire in
    // the same frame.
    if (state.isLoading) return false;

    state = const AsyncLoading();
    final result = await ref.read(generationOrchestratorProvider).generate(
          userId: user.id,
          projectId: projectId,
          type: type,
          prompt: prompt,
          attachmentUrls: attachmentUrls,
          options: options,
        );

    return result.when(
      success: (generation) {
        state = AsyncData(generation);
        ref.invalidate(generationsProvider);
        ref.invalidate(recentGenerationsProvider);
        if (projectId != null) {
          ref.invalidate(generationsByProjectProvider(projectId));
        }
        // A credit reservation/charge happened server-side even though this
        // call succeeded - refresh the balance so Home/Profile/generator
        // screens reflect it immediately, without requiring an app restart.
        ref.invalidate(creditSummaryProvider);
        return true;
      },
      failure: (error) {
        state = AsyncError(error, StackTrace.current);
        // A failed request may still have reserved (and been refunded) or
        // been rejected for insufficient credits - either way the balance
        // may have changed, so refresh it here too.
        ref.invalidate(creditSummaryProvider);
        return false;
      },
    );
  }

  void reset() => state = const AsyncData(null);
}

final createGenerationControllerProvider =
    AsyncNotifierProvider<CreateGenerationController, GenerationModel?>(
  CreateGenerationController.new,
);
