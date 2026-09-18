import 'ai_provider.dart';
import 'generation_service.dart';

class FunnelGenerationService extends GenerationService {
  FunnelGenerationService(this.provider);

  @override
  final FunnelAIProvider provider;
}
