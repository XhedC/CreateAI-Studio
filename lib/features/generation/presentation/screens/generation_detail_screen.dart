import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/constants/generation_status.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/audio_player_widget.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../../core/widgets/video_player_widget.dart';
// This shared detail screen renders every creation type, so - like its
// video/music branches - it needs a little type-specific knowledge. Video's
// equivalent pieces (VideoPollingController, VideoPlayerWidget) were placed
// in generation/core rather than video_generation specifically to avoid
// this screen depending on a leaf feature; a funnel's content is richer
// (a whole structured document living in its own table), so its lookup
// provider and schema live in funnel_generation's data/presentation layers
// instead of being duplicated here. This is the one deliberate exception to
// that direction - see docs/funnel-generation.md.
import '../../../funnel_generation/data/models/funnel_model.dart';
import '../../../funnel_generation/data/models/funnel_schema.dart';
import '../../../funnel_generation/presentation/providers/funnel_providers.dart';
import '../../data/models/generation_model.dart';
import '../providers/generation_providers.dart';
import '../providers/video_polling_provider.dart';

class GenerationDetailScreen extends ConsumerStatefulWidget {
  const GenerationDetailScreen({super.key, required this.generationId});

  final String generationId;

  @override
  ConsumerState<GenerationDetailScreen> createState() =>
      _GenerationDetailScreenState();
}

class _GenerationDetailScreenState extends ConsumerState<GenerationDetailScreen> {
  bool _isDownloading = false;
  bool _isSharing = false;
  bool _isRegenerating = false;

  Future<http.Response> _fetchResult(String url) => http.get(Uri.parse(url));

  bool _isMusic(GenerationModel generation) => generation.generationType == 'music';
  bool _isVideo(GenerationModel generation) => generation.generationType == 'video';
  bool _isFunnel(GenerationModel generation) => generation.generationType == 'funnel';

  String _audioExtension(GenerationModel generation) {
    final mimeType = generation.metadata['mimeType'] as String?;
    if (mimeType?.contains('wav') == true) return 'wav';
    if (mimeType?.contains('mp4') == true || mimeType?.contains('m4a') == true) return 'm4a';
    return 'mp3';
  }

  String _videoExtension(GenerationModel generation) {
    final path = generation.metadata['storagePath'] as String?;
    if (path != null && path.endsWith('.webm')) return 'webm';
    return 'mp4';
  }

  Future<void> _download(GenerationModel generation) async {
    if (generation.resultUrl == null) return;
    final isMusic = _isMusic(generation);
    final isVideo = _isVideo(generation);
    setState(() => _isDownloading = true);
    try {
      final response = await _fetchResult(generation.resultUrl!);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      if (isVideo) {
        // Video, like audio, is saved via a file picker/save dialog (modern
        // Android storage API, no broad storage permission needed) rather
        // than the photo gallery used for images.
        final path = await FilePicker.saveFile(
          fileName: 'createai-studio-video.${_videoExtension(generation)}',
          bytes: response.bodyBytes,
          type: FileType.video,
        );
        if (path == null) {
          if (mounted) setState(() => _isDownloading = false);
          return; // user cancelled the save dialog
        }
      } else if (isMusic) {
        // Audio isn't a "photo" - save it via a file picker/save dialog
        // (modern Android storage API, no broad storage permission needed)
        // rather than the photo gallery used for images.
        final path = await FilePicker.saveFile(
          fileName: 'createai-studio-music.${_audioExtension(generation)}',
          bytes: response.bodyBytes,
          type: FileType.audio,
        );
        if (path == null) {
          if (mounted) setState(() => _isDownloading = false);
          return; // user cancelled the save dialog
        }
      } else {
        await Gal.putImageBytes(response.bodyBytes, album: 'CreateAI Studio');
      }
      if (!mounted) return;
      final label = isVideo ? 'Video' : (isMusic ? 'Music' : 'Image');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label saved successfully.')),
      );
    } catch (_) {
      if (!mounted) return;
      final label = isVideo ? 'video' : (isMusic ? 'music' : 'image');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save the $label. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _share(GenerationModel generation) async {
    setState(() => _isSharing = true);
    final isMusic = _isMusic(generation);
    final isVideo = _isVideo(generation);
    try {
      if (generation.resultUrl != null) {
        final response = await _fetchResult(generation.resultUrl!);
        if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
        final fileName = isVideo
            ? 'createai-studio-video.${_videoExtension(generation)}'
            : isMusic
                ? 'createai-studio-music.${_audioExtension(generation)}'
                : 'createai-studio-image.png';
        final defaultMimeType = isVideo
            ? 'video/mp4'
            : isMusic
                ? 'audio/mpeg'
                : 'image/png';
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                response.bodyBytes,
                mimeType: response.headers['content-type'] ?? defaultMimeType,
                name: fileName,
              ),
            ],
            text: generation.prompt,
          ),
        );
      } else if (generation.resultText != null) {
        await SharePlus.instance.share(ShareParams(text: generation.resultText!));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to share right now. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _regenerate(GenerationModel generation) async {
    setState(() => _isRegenerating = true);
    final controller = ref.read(createGenerationControllerProvider.notifier);
    // Reuses the original prompt/settings but always creates a brand-new
    // generation row - the original is left untouched in History.
    final ok = await controller.submit(
      type: CreationType.fromValue(generation.generationType),
      prompt: generation.prompt,
      projectId: generation.projectId,
      options: generation.metadata,
    );
    if (!mounted) return;
    setState(() => _isRegenerating = false);

    if (ok) {
      final newGeneration = ref.read(createGenerationControllerProvider).value;
      controller.reset();
      if (newGeneration != null) {
        context.pushReplacement(RoutePaths.generationDetail(newGeneration.id));
      }
    } else {
      final error = ref.read(createGenerationControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error?.toString() ?? 'Regeneration failed. Please try again.')),
      );
    }
  }

  Future<void> _cancelVideo(GenerationModel generation) async {
    await ref.read(videoPollingProvider(generation.id).notifier).cancel();
  }

  Future<void> _duplicateFunnel(FunnelModel funnel) async {
    final ok = await ref.read(funnelDuplicateControllerProvider.notifier).duplicate(funnel);
    if (!mounted) return;
    if (ok) {
      final newFunnel = ref.read(funnelDuplicateControllerProvider).value;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Funnel duplicated.')),
      );
      if (newFunnel != null) {
        context.push(RoutePaths.generationDetail(newFunnel.generationId));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to duplicate the funnel. Please try again.')),
      );
    }
  }

  Future<void> _delete(GenerationModel generation) async {
    final label = _isFunnel(generation)
        ? 'funnel'
        : _isVideo(generation)
            ? 'video'
            : (_isMusic(generation) ? 'music' : 'image');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete this $label?'),
        content: const Text('This will permanently delete this generation and its files.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(generationRepositoryProvider)
        .deleteGenerationAndFiles(generation);
    ref.invalidate(generationsProvider);
    ref.invalidate(recentGenerationsProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final generationAsync = ref.watch(generationByIdProvider(widget.generationId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generation'),
        actions: [
          generationAsync.maybeWhen(
            data: (generation) => generation == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _delete(generation),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: generationAsync.when(
        loading: () => const LoadingWidget(),
        error: (_, __) => const AppErrorWidget(),
        data: (generation) {
          if (generation == null) {
            return const AppErrorWidget(message: 'This generation could not be found.');
          }
          final type = CreationType.fromValue(generation.generationType);
          final status = GenerationStatus.fromValue(generation.status);
          final filesAsync = ref.watch(generationFilesProvider(generation.id));

          if (_isVideo(generation) && status == GenerationStatus.processing) {
            final jobId = generation.metadata['jobId'] as String?;
            if (jobId != null) {
              // Resume/kick off polling for this generation's provider job.
              // start() is a no-op if already polling, so this is safe to
              // run on every rebuild (e.g. re-entering this screen).
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                ref.read(videoPollingProvider(generation.id).notifier).start(jobId);
              });
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      avatar: Icon(type.icon, size: 16, color: type.color),
                      label: Text(type.label),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      avatar: Icon(status.icon, size: 16, color: status.color),
                      label: Text(status.label),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Prompt',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(generation.prompt, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  '${DateFormatter.full(generation.createdAt)}'
                  '${generation.provider != null ? ' - ${generation.provider}/${generation.model}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (_isMusic(generation)) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in [
                        ('Genre', generation.metadata['genre']),
                        ('Mood', generation.metadata['mood']),
                        ('Duration', generation.metadata['duration']),
                      ])
                        if (entry.$2 != null && entry.$2 != 'none')
                          Chip(label: Text('${entry.$1}: ${entry.$2}')),
                    ],
                  ),
                ],
                if (_isVideo(generation)) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in [
                        ('Aspect ratio', generation.metadata['aspectRatio']),
                        ('Resolution', generation.metadata['resolution']),
                        ('Duration', generation.metadata['duration']),
                        ('Style', generation.metadata['style']),
                      ])
                        if (entry.$2 != null)
                          Chip(label: Text('${entry.$1}: ${entry.$2}')),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Text('Result',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _buildResult(context, generation, status),
                if (status == GenerationStatus.completed)
                  filesAsync.maybeWhen(
                    data: (files) => files.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: SizedBox(
                              height: 90,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: files.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (context, index) => ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: files[index].fileUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: files[index].fileUrl!,
                                          width: 90,
                                          height: 90,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 90,
                                          height: 90,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                        ),
                                ),
                              ),
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: status == GenerationStatus.completed &&
                                generation.resultUrl != null &&
                                !_isDownloading
                            ? () => _download(generation)
                            : null,
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_outlined),
                        label: const Text('Download'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: status == GenerationStatus.completed && !_isSharing
                            ? () => _share(generation)
                            : null,
                        icon: _isSharing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.share_outlined),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isRegenerating ? null : () => _regenerate(generation),
                    icon: _isRegenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(_isRegenerating ? 'Regenerating...' : 'Regenerate'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildResult(
    BuildContext context,
    GenerationModel generation,
    GenerationStatus status,
  ) {
    if (status == GenerationStatus.pending || status == GenerationStatus.processing) {
      if (_isVideo(generation)) {
        final isPolling = ref.watch(videoPollingProvider(generation.id));
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LoadingWidget(
                message: 'Creating your video. This can take a minute...',
              ),
            ),
            OutlinedButton.icon(
              onPressed: isPolling ? () => _cancelVideo(generation) : null,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel'),
            ),
          ],
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingWidget(message: 'Generating...'),
      );
    }
    if (status == GenerationStatus.cancelled) {
      return const AppErrorWidget(message: 'This generation was cancelled.');
    }
    if (status == GenerationStatus.failed) {
      return AppErrorWidget(
        message: generation.errorMessage ?? 'Generation failed.',
      );
    }
    if (_isFunnel(generation)) {
      return _buildFunnelSummary(context, generation);
    }
    if (generation.resultUrl != null && _isVideo(generation)) {
      return VideoPlayerWidget(url: generation.resultUrl!);
    }
    if (generation.resultUrl != null && _isMusic(generation)) {
      final colors = Theme.of(context).colorScheme;
      return Column(
        children: [
          Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.music_note_rounded, size: 56, color: colors.onPrimaryContainer),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: AudioPlayerWidget(
              generationId: generation.id,
              title: generation.prompt,
              url: generation.resultUrl!,
            ),
          ),
        ],
      );
    }
    if (generation.resultUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: generation.resultUrl!,
          placeholder: (context, url) => const LoadingWidget(),
          errorWidget: (context, url, error) => const AppErrorWidget(
            message: 'Preview unavailable.',
          ),
        ),
      );
    }
    if (generation.resultText != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(generation.resultText!),
      );
    }
    return const Text('No result yet.');
  }

  Widget _buildFunnelSummary(BuildContext context, GenerationModel generation) {
    final funnelAsync = ref.watch(funnelByGenerationIdProvider(generation.id));
    return funnelAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingWidget(),
      ),
      error: (_, __) => const AppErrorWidget(message: 'Could not load this funnel.'),
      data: (funnel) {
        if (funnel == null) {
          return const AppErrorWidget(message: 'This funnel could not be found.');
        }
        final colors = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.web_outlined, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      funnel.content.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (funnel.published ? colors.primary : colors.onSurfaceVariant)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      funnel.published ? 'Published' : (funnel.publicSlug != null ? 'Unpublished' : 'Draft'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: funnel.published ? colors.primary : colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${funnel.content.sections.length} sections - '
                '${FunnelType.fromValue(funnel.funnelType).label}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(RoutePaths.funnelPreview(funnel.id)),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.push(RoutePaths.funnelEditor(funnel.id)),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _duplicateFunnel(funnel),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Duplicate Funnel'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
