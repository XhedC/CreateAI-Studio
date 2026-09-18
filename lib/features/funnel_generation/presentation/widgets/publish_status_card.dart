import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/router/route_paths.dart';
import '../../data/models/funnel_model.dart';
import '../providers/funnel_providers.dart';

/// Publishing status + controls for the Funnel Editor - see
/// docs/PHASE_7_PUBLISHING.md "Publish button" / "Owner publishing
/// dashboard". Shows the current state (draft/published/unpublished),
/// the public URL once one exists, and the Publish/Republish/Unpublish
/// action appropriate to that state.
class PublishStatusCard extends ConsumerStatefulWidget {
  const PublishStatusCard({super.key, required this.funnel});

  final FunnelModel funnel;

  @override
  ConsumerState<PublishStatusCard> createState() => _PublishStatusCardState();
}

class _PublishStatusCardState extends ConsumerState<PublishStatusCard> {
  bool _isBusy = false;

  String _publicUrlFor(String slug) => EnvConfig.publicFunnelUrl(slug);

  Future<void> _confirmPublish() async {
    final funnel = widget.funnel;
    final isRepublish = funnel.published || funnel.publicSlug != null;
    final previewSlug = funnel.publicSlug ?? '<generated-on-publish>';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isRepublish ? 'Republish this funnel?' : 'Publish this funnel?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(funnel.content.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_publicUrlFor(previewSlug)),
            const SizedBox(height: 12),
            Text(
              isRepublish
                  ? 'Visitors will see your latest saved changes at this public URL.'
                  : 'Anyone with this URL will be able to view this funnel and submit '
                      'the lead form - no sign-in required.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isRepublish ? 'Republish' : 'Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    final ok = await ref.read(funnelPublishControllerProvider.notifier).publish(funnel.id);
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (ok) {
      final published = ref.read(funnelPublishControllerProvider).value;
      final slug = published?.publicSlug;
      if (!mounted || slug == null) return;
      await _showPublishedSuccess(slug);
    } else {
      final error = ref.read(funnelPublishControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error?.toString() ?? 'Unable to publish this funnel.')),
      );
    }
  }

  Future<void> _showPublishedSuccess(String slug) async {
    final url = _publicUrlFor(slug);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your funnel is now published.'),
        content: Text(url),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied.')),
              );
            },
            child: const Text('Copy Link'),
          ),
          TextButton(
            onPressed: () => SharePlus.instance.share(ShareParams(text: url)),
            child: const Text('Share'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push(RoutePaths.publicFunnel(slug));
            },
            child: const Text('View Published Funnel'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnpublish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unpublish this funnel?'),
        content: const Text(
          'Visitors will no longer be able to access the public page. Your draft '
          'is not affected, and you can publish again later at the same URL.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unpublish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    final ok = await ref.read(funnelPublishControllerProvider.notifier).unpublish(widget.funnel.id);
    if (!mounted) return;
    setState(() => _isBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Funnel unpublished.' : 'Unable to unpublish this funnel.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final funnel = widget.funnel;
    final colors = Theme.of(context).colorScheme;

    final Color badgeColor;
    final String badgeLabel;
    if (funnel.published) {
      badgeColor = colors.primary;
      badgeLabel = 'Published';
    } else if (funnel.publicSlug != null) {
      badgeColor = colors.error;
      badgeLabel = 'Unpublished';
    } else {
      badgeColor = colors.onSurfaceVariant;
      badgeLabel = 'Draft';
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: badgeColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (funnel.publishedAt != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Published ${funnel.publishedAt!.toLocal()}'.split('.').first,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            if (funnel.published && funnel.hasUnpublishedChanges) ...[
              const SizedBox(height: 8),
              Text(
                'You have unsaved changes since this was last published - '
                'visitors still see the previous version until you republish.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ],
            if (funnel.publicSlug != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _publicUrlFor(funnel.publicSlug!),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy link',
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _publicUrlFor(funnel.publicSlug!)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied.')),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.share_outlined, size: 20),
                    onPressed: () => SharePlus.instance
                        .share(ShareParams(text: _publicUrlFor(funnel.publicSlug!))),
                  ),
                ],
              ),
            ],
            if (funnel.publicSlug != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(RoutePaths.publicFunnel(funnel.publicSlug!)),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview Published Version'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (funnel.published)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isBusy ? null : _confirmPublish,
                      icon: _isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.public_rounded),
                      label: const Text('Republish'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _confirmUnpublish,
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: const Text('Unpublish'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : _confirmPublish,
                  icon: _isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.public_rounded),
                  label: Text(funnel.publicSlug != null ? 'Republish' : 'Publish'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
