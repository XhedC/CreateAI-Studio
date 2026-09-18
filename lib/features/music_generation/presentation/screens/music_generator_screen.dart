import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../credits/presentation/providers/credits_providers.dart';
import '../../../credits/presentation/widgets/generation_cost_label.dart';
import '../../../credits/presentation/widgets/insufficient_credits_dialog.dart';
import '../../../generation/presentation/providers/generation_providers.dart';
import '../../../generation/services/ai_provider.dart';
import '../providers/music_generation_providers.dart';
import '../widgets/music_settings_panel.dart';

class MusicGeneratorScreen extends ConsumerStatefulWidget {
  const MusicGeneratorScreen({super.key});

  @override
  ConsumerState<MusicGeneratorScreen> createState() => _MusicGeneratorScreenState();
}

class _MusicGeneratorScreenState extends ConsumerState<MusicGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _promptController = TextEditingController();
  final _lyricsController = TextEditingController();
  bool _generateLyricsAutomatically = false;
  bool _isGeneratingLyrics = false;

  @override
  void dispose() {
    _promptController.dispose();
    _lyricsController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    var lyrics = _lyricsController.text.trim();

    if (_generateLyricsAutomatically && lyrics.isEmpty) {
      setState(() => _isGeneratingLyrics = true);
      // Reuses Phase 1's text-generation architecture rather than
      // inventing a separate lyrics pipeline.
      final lyricsResult = await ref.read(textGenerationServiceProvider).generate(
            AIGenerationRequest(
              prompt: 'Write short, singable song lyrics (2 verses and a '
                  'chorus) for a song described as: '
                  '${_promptController.text.trim()}',
            ),
          );
      if (!mounted) return;
      setState(() => _isGeneratingLyrics = false);
      lyrics = lyricsResult.resultText?.trim() ?? '';
      if (lyrics.isNotEmpty) {
        _lyricsController.text = lyrics;
      }
    }

    final settings = ref.read(musicSettingsProvider);
    final controller = ref.read(createGenerationControllerProvider.notifier);
    final ok = await controller.submit(
      type: CreationType.music,
      prompt: _promptController.text,
      options: {
        ...settings.toJson(),
        if (lyrics.isNotEmpty) 'lyrics': lyrics,
      },
    );

    if (!mounted) return;

    if (ok) {
      final generation = ref.read(createGenerationControllerProvider).value;
      _promptController.clear();
      _lyricsController.clear();
      ref.read(musicSettingsProvider.notifier).reset();
      controller.reset();
      if (generation != null) {
        context.push(RoutePaths.generationDetail(generation.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createGenerationControllerProvider);
    final isGenerating = createState.isLoading || _isGeneratingLyrics;
    final creditsAsync = ref.watch(creditSummaryProvider);

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
      appBar: AppBar(title: const Text('AI Music Generator')),
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
                'Describe the music you want to create...',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Example: Create an uplifting acoustic worship song about '
                'hope and faith.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _promptController,
                maxLines: 4,
                minLines: 2,
                maxLength: Validators.maxMusicPromptLength,
                enabled: !isGenerating,
                validator: Validators.musicPrompt,
                decoration: const InputDecoration(
                  hintText: 'Describe the music you want to create...',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Lyrics (optional)',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Generate automatically',
                          style: Theme.of(context).textTheme.bodySmall),
                      Switch(
                        value: _generateLyricsAutomatically,
                        onChanged: isGenerating
                            ? null
                            : (value) => setState(() => _generateLyricsAutomatically = value),
                      ),
                    ],
                  ),
                ],
              ),
              TextFormField(
                controller: _lyricsController,
                maxLines: 6,
                minLines: 3,
                maxLength: Validators.maxLyricsLength,
                enabled: !isGenerating && !_generateLyricsAutomatically,
                validator: Validators.lyrics,
                decoration: InputDecoration(
                  hintText: _generateLyricsAutomatically
                      ? 'AI will write lyrics for you...'
                      : 'Enter lyrics or let AI create lyrics...',
                ),
              ),
              const SizedBox(height: 8),
              const MusicSettingsPanel(),
              const SizedBox(height: 12),
              const GenerationCostLabel(generationType: 'music'),
              const SizedBox(height: 4),
              AppButton(
                label: 'Generate Music',
                icon: Icons.music_note_rounded,
                isLoading: isGenerating,
                onPressed: _generate,
              ),
              if (isGenerating) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    _isGeneratingLyrics ? 'Writing lyrics...' : 'Creating your music...',
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
