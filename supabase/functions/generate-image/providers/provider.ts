import type {
  GeneratedImageFile,
  ImageSettings,
  ProviderGenerationResult,
} from "../types.ts";

export interface ImageGenerationRequest {
  prompt: string;
  settings: ImageSettings;
  /** Reference image bytes, already downloaded server-side, if provided. */
  referenceImage?: GeneratedImageFile | null;
}

/**
 * Every AI image vendor integration implements this - mirrors the
 * `ImageAIProvider` abstraction on the Flutter side
 * (lib/features/generation/services/ai_provider.dart) so the "swap one
 * implementation" story is symmetric on both ends of the stack.
 */
export interface ImageGenerationProvider {
  readonly name: string;
  generate(request: ImageGenerationRequest): Promise<ProviderGenerationResult>;
}
