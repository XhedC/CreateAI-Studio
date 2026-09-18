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
import '../../../image_generation/data/models/reference_image.dart';
import '../../data/models/funnel_schema.dart';
import '../providers/funnel_providers.dart';
import '../widgets/funnel_image_picker_field.dart';

class FunnelGeneratorScreen extends ConsumerStatefulWidget {
  const FunnelGeneratorScreen({super.key});

  @override
  ConsumerState<FunnelGeneratorScreen> createState() => _FunnelGeneratorScreenState();
}

class _FunnelGeneratorScreenState extends ConsumerState<FunnelGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _promptController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _businessTypeController = TextEditingController();
  final _productController = TextEditingController();
  final _audienceController = TextEditingController();
  final _offerController = TextEditingController();
  final _ctaController = TextEditingController();
  bool _isUploadingImages = false;

  @override
  void dispose() {
    _promptController.dispose();
    _businessNameController.dispose();
    _businessTypeController.dispose();
    _productController.dispose();
    _audienceController.dispose();
    _offerController.dispose();
    _ctaController.dispose();
    super.dispose();
  }

  Future<String?> _uploadIfPresent(String userId, ReferenceImage? referenceImage) async {
    if (referenceImage == null) return null;
    final uploadResult = await ref.read(fileUploadServiceProvider).uploadUserFile(
          userId: userId,
          file: referenceImage.file,
          fileName: '${DateTime.now().millisecondsSinceEpoch}_${referenceImage.fileName}',
          mimeType: referenceImage.mimeType,
        );
    return uploadResult.when(
      success: (uploaded) => uploaded.storagePath,
      failure: (_) => null,
    );
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    setState(() => _isUploadingImages = true);
    final logoImage = ref.read(funnelLogoImageProvider);
    final productImage = ref.read(funnelProductImageProvider);
    final logoPath = await _uploadIfPresent(user.id, logoImage);
    final productImagePath = await _uploadIfPresent(user.id, productImage);
    if (!mounted) return;
    setState(() => _isUploadingImages = false);

    final selection = ref.read(funnelSelectionProvider);
    final controller = ref.read(createGenerationControllerProvider.notifier);
    final ok = await controller.submit(
      type: CreationType.funnel,
      prompt: _promptController.text,
      options: {
        'funnelType': selection.funnelType.value,
        'businessName': _businessNameController.text.trim(),
        'businessType': _businessTypeController.text.trim(),
        'product': _productController.text.trim(),
        'targetAudience': _audienceController.text.trim(),
        'goal': selection.goal.value,
        'offer': _offerController.text.trim(),
        'cta': _ctaController.text.trim(),
        if (logoPath != null) 'logoPath': logoPath,
        if (productImagePath != null) 'productImagePath': productImagePath,
      },
    );

    if (!mounted) return;

    if (ok) {
      final generation = ref.read(createGenerationControllerProvider).value;
      _promptController.clear();
      ref.read(funnelLogoImageProvider.notifier).clear();
      ref.read(funnelProductImageProvider.notifier).clear();
      ref.read(funnelSelectionProvider.notifier).reset();
      controller.reset();
      if (generation != null) {
        context.push(RoutePaths.generationDetail(generation.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createGenerationControllerProvider);
    final isGenerating = createState.isLoading || _isUploadingImages;
    final creditsAsync = ref.watch(creditSummaryProvider);
    final selection = ref.watch(funnelSelectionProvider);

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
      appBar: AppBar(title: const Text('AI Funnel Builder')),
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
              Text('Describe the funnel you want to create...',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Example: Create a landing page for a pharmacy offering online '
                'consultation and medicine delivery.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _promptController,
                maxLines: 4,
                minLines: 3,
                maxLength: Validators.maxFunnelPromptLength,
                enabled: !isGenerating,
                validator: Validators.funnelPrompt,
                decoration: const InputDecoration(
                  hintText: 'Describe the funnel you want to create...',
                ),
              ),
              const SizedBox(height: 8),
              Text('Business information (optional)',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _businessNameController,
                enabled: !isGenerating,
                validator: Validators.businessName,
                decoration: const InputDecoration(labelText: 'Business Name'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _businessTypeController,
                enabled: !isGenerating,
                decoration: const InputDecoration(labelText: 'Business Type'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _productController,
                enabled: !isGenerating,
                decoration: const InputDecoration(labelText: 'Product / Service'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _audienceController,
                enabled: !isGenerating,
                decoration: const InputDecoration(labelText: 'Target Audience'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _offerController,
                enabled: !isGenerating,
                decoration: const InputDecoration(labelText: 'Offer'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ctaController,
                enabled: !isGenerating,
                decoration: const InputDecoration(labelText: 'Call To Action'),
              ),
              const SizedBox(height: 16),
              Text('Funnel type',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<FunnelType>(
                value: selection.funnelType,
                items: [
                  for (final type in FunnelType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: isGenerating
                    ? null
                    : (value) {
                        if (value != null) {
                          ref.read(funnelSelectionProvider.notifier).setFunnelType(value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              Text('Main goal',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final goal in FunnelGoal.values)
                    ChoiceChip(
                      label: Text(goal.label),
                      selected: selection.goal == goal,
                      onSelected: isGenerating
                          ? null
                          : (_) => ref.read(funnelSelectionProvider.notifier).setGoal(goal),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Logo (optional)',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              FunnelImagePickerField(provider: funnelLogoImageProvider, label: 'Upload Logo'),
              const SizedBox(height: 16),
              Text('Product / reference image (optional)',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              FunnelImagePickerField(
                provider: funnelProductImageProvider,
                label: 'Upload Product / Reference Image',
              ),
              const SizedBox(height: 16),
              const GenerationCostLabel(generationType: 'funnel'),
              const SizedBox(height: 4),
              AppButton(
                label: 'Generate Funnel',
                icon: Icons.web_outlined,
                isLoading: isGenerating,
                onPressed: _generate,
              ),
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
