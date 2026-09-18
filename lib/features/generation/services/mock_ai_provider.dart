import 'ai_provider.dart';

/// Phase 1 stand-in for a real AI backend call. No paid API is ever invoked -
/// each provider simulates network latency and returns a clearly-labelled
/// placeholder result so the full generation pipeline (pending -> processing
/// -> completed -> history) can be exercised end to end.
///
/// Swapping this out later means writing one new class per type that
/// implements the matching `*AIProvider` interface (e.g. a real
/// `OpenAiImageProvider implements ImageAIProvider` that calls a Supabase
/// Edge Function) and updating the provider wiring in
/// `generation_providers.dart` - nothing else in the app changes.
mixin _MockLatency {
  Future<void> simulateWork() =>
      Future.delayed(const Duration(milliseconds: 1200));
}

class MockTextAIProvider extends TextAIProvider with _MockLatency {
  @override
  String get providerName => 'mock';
  @override
  String get modelName => 'mock-text-v1';

  @override
  Future<AIGenerationResult> generate(AIGenerationRequest request) async {
    await simulateWork();
    return AIGenerationResult(
      resultText:
          '[Mock AI response]\n\nHere is placeholder text generated for the '
          'prompt: "${request.prompt}". Connect a real text provider in a '
          'later phase to replace this with an actual AI completion.',
      metadata: {'mock': true, 'wordCount': request.prompt.split(' ').length},
    );
  }
}

class MockImageAIProvider extends ImageAIProvider with _MockLatency {
  @override
  String get providerName => 'mock';
  @override
  String get modelName => 'mock-image-v1';

  @override
  Future<AIGenerationResult> generate(AIGenerationRequest request) async {
    await simulateWork();
    const placeholder = 'https://placehold.co/1024x1024?text=AI+Image';
    return const AIGenerationResult(
      resultUrl: placeholder,
      thumbnailUrl: placeholder,
      metadata: {'mock': true, 'width': 1024, 'height': 1024},
    );
  }
}

class MockMusicAIProvider extends MusicAIProvider with _MockLatency {
  @override
  String get providerName => 'mock';
  @override
  String get modelName => 'mock-music-v1';

  @override
  Future<AIGenerationResult> generate(AIGenerationRequest request) async {
    await simulateWork();
    return const AIGenerationResult(
      resultUrl: null,
      metadata: {'mock': true, 'durationSeconds': 30},
      resultText: '[Mock] A 30-second track would be generated here.',
    );
  }
}

class MockVideoAIProvider extends VideoAIProvider with _MockLatency {
  @override
  String get providerName => 'mock';
  @override
  String get modelName => 'mock-video-v1';

  @override
  Future<AIGenerationResult> generate(AIGenerationRequest request) async {
    await simulateWork();
    const placeholder = 'https://placehold.co/1280x720?text=AI+Video';
    return const AIGenerationResult(
      resultUrl: null,
      thumbnailUrl: placeholder,
      metadata: {'mock': true, 'durationSeconds': 8},
      resultText: '[Mock] An 8-second video would be generated here.',
    );
  }
}

class MockFunnelAIProvider extends FunnelAIProvider with _MockLatency {
  @override
  String get providerName => 'mock';
  @override
  String get modelName => 'mock-funnel-v1';

  @override
  Future<AIGenerationResult> generate(AIGenerationRequest request) async {
    await simulateWork();
    return AIGenerationResult(
      resultText:
          '[Mock AI response]\n\nLanding page outline for: "${request.prompt}"\n\n'
          '1. Hero section\n2. Benefits\n3. Social proof\n4. Call to action',
      metadata: {'mock': true, 'sections': 4},
    );
  }
}
