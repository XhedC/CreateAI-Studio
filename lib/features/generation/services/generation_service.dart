import '../../../core/constants/creation_type.dart';
import 'ai_provider.dart';

/// Base for the per-category services. Each concrete service just pins the
/// [AIProvider] subtype it accepts - the actual call is always delegated to
/// the injected provider, which is what makes swapping providers a
/// one-line change in `generation_providers.dart`.
abstract class GenerationService {
  AIProvider get provider;

  CreationType get type => provider.type;

  Future<AIGenerationResult> generate(AIGenerationRequest request) {
    return provider.generate(request);
  }
}
