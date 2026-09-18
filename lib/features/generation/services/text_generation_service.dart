import 'ai_provider.dart';
import 'generation_service.dart';

class TextGenerationService extends GenerationService {
  TextGenerationService(this.provider);

  @override
  final TextAIProvider provider;
}
