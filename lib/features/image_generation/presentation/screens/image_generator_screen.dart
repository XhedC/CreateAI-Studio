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
import '../providers/image_generation_providers.dart';
import '../widgets/image_settings_panel.dart';
import '../widgets/reference_image_picker_field.dart';

class ImageGeneratorScreen extends ConsumerStatefulWidget {
  const ImageGeneratorScreen({super.key});

  @override
  ConsumerState<ImageGeneratorScreen> createState() => _ImageGeneratorScreenState();
}

class _ImageGeneratorScreenState extends ConsumerState<ImageGeneratorScreen> {
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

    final settings = ref.read(imageSettingsProvider);
    final controller = ref.read(createGenerationControllerProvider.notifier);
    final ok = await controller.submit(
      type: CreationType.image,
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
      ref.read(imageSettingsProvider.notifier).reset();
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
    final numberOfImages = ref.watch(imageSettingsProvider).numberOfImages;

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
      appBar: AppBar(title: const Text('AI Image Generator')),
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
                'Describe the image you want to create...',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Example: Create a modern pharmacy advertisement with a '
                'clean medical design.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _promptController,
                maxLines: 5,
                minLines: 3,
                maxLength: Validators.maxImagePromptLength,
                enabled: !isGenerating,
                validator: Validators.imagePrompt,
                decoration: const InputDecoration(
                  hintText: 'Describe the image you want to create...',
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
              const ImageSettingsPanel(),
              const SizedBox(height: 12),
              GenerationCostLabel(generationType: 'image', multiplier: numberOfImages),
              const SizedBox(height: 4),
              AppButton(
                label: 'Generate Image',
                icon: Icons.auto_awesome_rounded,
                isLoading: isGenerating,
                onPressed: _generate,
              ),
              // AppButton swaps its label for a spinner while isLoading, so
              // the "Creating your image..." status lives here instead -
              // it stays visible (and announced to screen readers) for the
              // whole generation, not just the button's own busy state.
              if (isGenerating) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Creating your image...',
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
