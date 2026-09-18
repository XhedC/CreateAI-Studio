import '../../../core/constants/creation_type.dart';

/// Everything an [AIProvider] needs to fulfil one generation request.
class AIGenerationRequest {
  const AIGenerationRequest({
    required this.prompt,
    this.attachmentUrls = const [],
    this.options = const {},
    this.generationId,
  });

  final String prompt;

  /// Publicly-readable URLs (or storage paths) of files the user uploaded,
  /// forwarded to the provider as reference/input material.
  final List<String> attachmentUrls;

  /// Placeholder for per-type advanced options (aspect ratio, duration,
  /// voice, tone, ...). Providers read whatever keys they understand and
  /// ignore the rest, so the UI can grow this map without breaking anything.
  final Map<String, dynamic> options;

  /// The id of the `generations` row this request is fulfilling - already
  /// created (status: pending/processing) by [GenerationOrchestrator] before
  /// the provider is ever called. Most providers don't need this (they just
  /// return a result the orchestrator persists onto that same row), but a
  /// provider that must itself write to a *different* table linked back to
  /// this generation (e.g. `EdgeFunctionFunnelProvider` inserting into
  /// `funnels`) needs it to establish that link server-side - never trust a
  /// client-supplied generation id without also verifying ownership there.
  final String? generationId;
}

/// What every [AIProvider] returns, normalized so [GenerationRepository] can
/// persist it into `generations` without knowing which provider produced it.
class AIGenerationResult {
  const AIGenerationResult({
    this.resultText,
    this.resultUrl,
    this.thumbnailUrl,
    this.metadata = const {},
    this.additionalFiles = const [],
    this.isPending = false,
  });

  final String? resultText;
  final String? resultUrl;
  final String? thumbnailUrl;
  final Map<String, dynamic> metadata;

  /// Extra output files beyond the primary result (e.g. images 2-4 of a
  /// multi-image request). Persisted into the existing `generation_files`
  /// table - most providers return an empty list and never think about this.
  final List<GenerationResultFile> additionalFiles;

  /// True when the provider has only *started* a job and has no final
  /// result yet (genuinely asynchronous generation, e.g. video). When true,
  /// [GenerationOrchestrator] leaves the generation's status as
  /// `processing` (merging [metadata] - typically a provider job id -
  /// rather than marking it `completed`) instead of treating this as the
  /// final answer. A separate poller (see
  /// `lib/features/generation/services/video_status_checker.dart`) is
  /// responsible for eventually completing it. Every provider that doesn't
  /// set this behaves exactly as before.
  final bool isPending;
}

/// One additional output file attached to a generation, stored via
/// [GenerationRepository.attachFile].
class GenerationResultFile {
  const GenerationResultFile({
    required this.fileName,
    required this.mimeType,
    required this.storagePath,
    this.fileUrl,
    this.fileSize,
  });

  final String fileName;
  final String mimeType;
  final String storagePath;
  final String? fileUrl;
  final int? fileSize;
}

/// The contract every AI backend integration must implement, regardless of
/// vendor. The UI and [GenerationOrchestrator] only ever depend on this
/// interface - swapping a mock for a real provider (OpenAI, Stability,
/// ElevenLabs, Runway, ...) later never touches app or database code.
abstract class AIProvider {
  CreationType get type;

  /// Stored in `generations.provider` (e.g. "openai", "stability", "mock").
  String get providerName;

  /// Stored in `generations.model` (e.g. "gpt-5", "sdxl", "mock-v1").
  String get modelName;

  Future<AIGenerationResult> generate(AIGenerationRequest request);
}

abstract class TextAIProvider implements AIProvider {
  @override
  CreationType get type => CreationType.text;
}

abstract class ImageAIProvider implements AIProvider {
  @override
  CreationType get type => CreationType.image;
}

abstract class MusicAIProvider implements AIProvider {
  @override
  CreationType get type => CreationType.music;
}

abstract class VideoAIProvider implements AIProvider {
  @override
  CreationType get type => CreationType.video;
}

abstract class FunnelAIProvider implements AIProvider {
  @override
  CreationType get type => CreationType.funnel;
}
