import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/video_segment_model.dart';

class SegmentCard extends StatelessWidget {
  const SegmentCard({
    super.key,
    required this.segment,
    required this.index,
    this.onTap,
    this.onDelete,
    this.onRetry,
  });

  final VideoSegmentModel segment;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;

  IconData get _inputIcon => switch (segment.inputType) {
        SegmentInputType.text => Icons.text_fields_rounded,
        SegmentInputType.photo => Icons.photo_camera_rounded,
        SegmentInputType.voice => Icons.mic_rounded,
      };

  Color _statusColor(ColorScheme colors) => switch (segment.status) {
        SegmentStatus.pending => colors.outline,
        SegmentStatus.processing => colors.tertiary,
        SegmentStatus.completed => colors.primary,
        SegmentStatus.failed => colors.error,
      };

  String get _statusLabel => switch (segment.status) {
        SegmentStatus.pending => 'Pending',
        SegmentStatus.processing => 'Generating...',
        SegmentStatus.completed => 'Ready',
        SegmentStatus.failed => 'Failed',
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = _statusColor(colors);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // Thumbnail / status area
            Container(
              width: 80,
              height: 72,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
              child: segment.thumbnailUrl != null
                  ? ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: segment.thumbnailUrl!,
                        fit: BoxFit.cover,
                        width: 80,
                        height: 72,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (segment.isProcessing)
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: statusColor,
                            ),
                          )
                        else
                          Icon(_inputIcon, color: statusColor, size: 28),
                        const SizedBox(height: 4),
                        Text(
                          '#${index + 1}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _statusLabel,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${segment.durationSeconds}s',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      segment.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (segment.isFailed && onRetry != null)
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: colors.error, size: 20),
                    onPressed: onRetry,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Retry',
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: colors.onSurfaceVariant, size: 18),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
