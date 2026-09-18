import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../credits/presentation/providers/credits_providers.dart';
import '../../../credits/presentation/widgets/generation_cost_label.dart';
import '../../../credits/presentation/widgets/insufficient_credits_dialog.dart';
import '../../../generation/presentation/providers/generation_providers.dart';
// Reused as-is from image_generation - the reference-image concept (model,
// validator, and picker widget) isn't image-specific, so Video reuses it
// directly instead of duplicating a second copy. See docs/video-generation.md.
import '../../../image_generation/presentation/providers/image_generation_providers.dart'
    show referenceImageProvider;
import '../../../image_generation/presentation/widgets/reference_image_picker_field.dart';
import '../providers/video_generation_providers.dart';
import '../widgets/video_settings_panel.dart';

class VideoGeneratorScreen extends ConsumerStatefulWidget {
  const VideoGeneratorScreen({super.key});

  @override
  ConsumerState<VideoGeneratorScreen> createState() => _VideoGeneratorScreenState();
}

class _VideoGeneratorScreenState extends ConsumerState<VideoGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _promptController = TextEditingController();
  bool _isUploadingReference = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    String? referenceStoragePath;
    final referenceImage = ref.read(referenceImageProvider);
    if (referenceImage != null) {
      setState(() => _isUploadingReference = true);
      final uploadResult = await ref.read(fileUploadServiceProvider).uploadUserFile(
            userId: user.id,
            file: referenceImage.file,
            fileName:
                '${DateTime.now().millisecondsSinceEpoch}_${referenceImage.fileName}',
            mimeType: referenceImage.mimeType,
          );
      if (!mounted) return;
      setState(() => _isUploadingReference = false);

      final uploadFailed = uploadResult.when(
        success: (uploaded) {
          referenceStoragePath = uploaded.storagePath;
          return false;
        },
        failure: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
          return true;
        },
      );
      if (uploadFailed) return;
    }

    final settings = ref.read(videoSettingsProvider);
    final controller = ref.read(createGenerationControllerProvider.notifier);
    final ok = await controller.submit(
      type: CreationType.video,
      prompt: _promptController.text,
      attachmentUrls: [
        if (referenceStoragePath != null) referenceStoragePath!,
      ],
      options: settings.toJson(),
    );

    if (!mounted) return;

    if (ok) {
      final generation = ref.read(createGenerationControllerProvider).value;
      _promptController.clear();
      ref.read(referenceImageProvider.notifier).clear();
      ref.read(videoSettingsProvider.notifier).reset();
      controller.reset();
      if (generation != null) {
        context.push(RoutePaths.generationDetail(generation.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createGenerationControllerProvider);
    final isGenerating = createState.isLoading || _isUploadingReference;
    final creditsAsync = ref.watch(creditSummaryProvider);
    final hasReferenceImage = ref.watch(referenceImageProvider) != null;

    ref.listen(createGenerationControllerProvider, (previous, next) {
      if (next is AsyncError && next.error is AppException) {
        final error = next.error as AppException;
        if (error.code == 'INSUFFICIENT_CREDITS') {
          showInsufficientCreditsDialog(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('AI Video Generator')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              creditsAsync.maybeWhen(
                data: (summary) => summary.creditsRemaining <= 0
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _LowCreditsBanner(planName: summary.planName),
                      )
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
              Text(
                'Describe the video you want to create...',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Example: Create a cinematic advertisement for a modern '
                'pharmacy, with a clean professional atmosphere and smooth '
                'camera movement.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Optional if you upload a reference image below.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _promptController,
                maxLines: 5,
                minLines: 3,
                maxLength: Validators.maxVideoPromptLength,
                enabled: !isGenerating,
                validator: (value) =>
                    Validators.videoPrompt(value, hasReferenceImage: hasReferenceImage),
                decoration: const InputDecoration(
                  hintText: 'Describe the video you want to create...',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reference Image (optional)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const ReferenceImagePickerField(),
              const SizedBox(height: 8),
              const VideoSettingsPanel(),
              const SizedBox(height: 12),
              const GenerationCostLabel(generationType: 'video'),
              const SizedBox(height: 4),
              AppButton(
                label: 'Generate Video',
                icon: Icons.movie_creation_outlined,
                isLoading: isGenerating,
                onPressed: _generate,
              ),
              if (isGenerating) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Starting your video...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LowCreditsBanner extends StatelessWidget {
  const _LowCreditsBanner({required this.planName});

  final String planName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_outlined, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're out of credits on the $planName plan. Generation may be blocked until more are available.",
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
