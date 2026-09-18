import '../../../core/constants/creation_type.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/network_service.dart';
import '../../../core/utils/result.dart';
import '../data/models/generation_model.dart';
import '../data/repositories/generation_repository.dart';
import 'ai_provider.dart';

/// The single reusable generation workflow every creation type goes through:
///
/// validate request -> create `generations` row (status=pending) -> call the
/// [AIProvider] for the requested [CreationType] -> persist the result and
/// mark completed, or persist a friendly error and mark failed.
///
/// The UI (Create screen) only ever talks to this class; it never calls a
/// provider or the repository directly, so adding a 6th creation type later
/// means adding one provider + one entry in [providersByType] - this class
/// does not change.
class GenerationOrchestrator {
  GenerationOrchestrator({
    required GenerationRepository repository,
    required NetworkService networkService,
    required Map<CreationType, AIProvider> providersByType,
  })  : _repository = repository,
        _networkService = networkService,
        _providersByType = providersByType;

  final GenerationRepository _repository;
  final NetworkService _networkService;
  final Map<CreationType, AIProvider> _providersByType;

  Future<Result<GenerationModel>> generate({
    required String userId,
    String? projectId,
    required CreationType type,
    required String prompt,
    List<String> attachmentUrls = const [],
    Map<String, dynamic> options = const {},
  }) async {
    final trimmedPrompt = prompt.trim();
    // Every type built so far (text/image/music) always requires a prompt
    // and their own screens validate that before ever calling submit(). The
    // one exception is video's Image -> Video mode, where a reference image
    // alone is a valid request - so an empty prompt is only rejected here if
    // there's no attachment to fall back on either.
    if (trimmedPrompt.isEmpty && attachmentUrls.isEmpty) {
      return const Result.failure(
        ValidationException('Please describe what you would like to create.'),
      );
    }

    if (!await _networkService.isConnected) {
      return const Result.failure(NetworkException());
    }

    final provider = _providersByType[type];
    if (provider == null) {
      return Result.failure(
        GenerationException(message: '${type.label} is not available yet.'),
      );
    }

    final createResult = await _repository.createGeneration(
      userId: userId,
      projectId: projectId,
      generationType: type.value,
      prompt: trimmedPrompt,
    );

    return createResult.when(
      success: (generation) async {
        await _repository.updateGeneration(generation.id, status: 'processing');

        try {
          final result = await provider.generate(
            AIGenerationRequest(
              prompt: trimmedPrompt,
              attachmentUrls: attachmentUrls,
              options: options,
              generationId: generation.id,
            ),
          );

          // Some providers (e.g. EdgeFunctionImageProvider) don't know which
          // concrete backend served the request until the call returns -
          // the backend decides mock vs. real provider. Metadata wins over
          // the static provider/model identity when present; providers that
          // don't set these keys behave exactly as before.
          final actualProvider =
              result.metadata['provider'] as String? ?? provider.providerName;
          final actualModel =
              result.metadata['model'] as String? ?? provider.modelName;

          if (result.isPending) {
            // Genuinely async generation (video): the provider only started
            // a job. Leave status as processing (already set above) and
            // just record the provider/model/jobId - a separate poller
            // (VideoStatusPoller) is responsible for eventually completing
            // or failing this generation.
            return _repository.updateGeneration(
              generation.id,
              status: 'processing',
              provider: actualProvider,
              model: actualModel,
              metadata: result.metadata,
            );
          }

          final updated = await _repository.updateGeneration(
            generation.id,
            status: 'completed',
            provider: actualProvider,
            model: actualModel,
            resultText: result.resultText,
            resultUrl: result.resultUrl,
            thumbnailUrl: result.thumbnailUrl,
            metadata: result.metadata,
            completedAt: DateTime.now(),
          );

          for (final file in result.additionalFiles) {
            await _repository.attachFile(
              generationId: generation.id,
              userId: userId,
              fileName: file.fileName,
              fileType: type.value,
              mimeType: file.mimeType,
              storagePath: file.storagePath,
              fileUrl: file.fileUrl,
              fileSize: file.fileSize,
            );
          }

          return updated;
        } catch (e) {
          final message = e is AppException
              ? e.message
              : 'Generation failed. Please try again.';
          await _repository.updateGeneration(
            generation.id,
            status: 'failed',
            errorMessage: message,
            completedAt: DateTime.now(),
          );
          return Result.failure(
            GenerationException(message: message, cause: e),
          );
        }
      },
      failure: (error) async => Result.failure(error),
    );
  }
}
