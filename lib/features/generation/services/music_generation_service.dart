import 'ai_provider.dart';
import 'generation_service.dart';

class MusicGenerationService extends GenerationService {
  MusicGenerationService(this.provider);

  @override
  final MusicAIProvider provider;
}
