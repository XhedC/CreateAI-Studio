import 'ai_provider.dart';
import 'generation_service.dart';

class VideoGenerationService extends GenerationService {
  VideoGenerationService(this.provider);

  @override
  final VideoAIProvider provider;
}
