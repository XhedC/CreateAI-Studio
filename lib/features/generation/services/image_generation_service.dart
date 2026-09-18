import 'ai_provider.dart';
import 'generation_service.dart';

class ImageGenerationService extends GenerationService {
  ImageGenerationService(this.provider);

  @override
  final ImageAIProvider provider;
}
