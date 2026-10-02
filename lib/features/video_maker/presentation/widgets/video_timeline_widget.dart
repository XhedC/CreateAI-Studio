import 'package:flutter/material.dart';

import '../../data/models/video_segment_model.dart';
import '../../data/models/video_story_model.dart';

class VideoTimelineWidget extends StatelessWidget {
  const VideoTimelineWidget({
    super.key,
    required this.story,
    this.selectedSegmentIndex,
    this.onSegmentTap,
  });

  final VideoStoryModel story;
  final int? selectedSegmentIndex;
  final ValueChanged<int>? onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final segments = story.segments;

    if (segments.isEmpty) {
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No segments yet. Add your first clip!',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    final totalDuration = story.totalDurationSeconds.clamp(1, 9999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Timeline',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              '${story.completedSegments}/${segments.length} clips  |  ${_formatDuration(story.totalDurationSeconds)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Timeline bar
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              for (int i = 0; i < segments.length; i++) ...[
                if (i > 0)
                  Container(width: 1, color: colors.outlineVariant),
                Expanded(
                  flex: (segments[i].durationSeconds * 100 ~/ totalDuration)
                      .clamp(1, 100),
                  child: _TimelineSegment(
                    segment: segments[i],
                    index: i,
                    isSelected: selectedSegmentIndex == i,
                    onTap: onSegmentTap != null ? () => onSegmentTap!(i) : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Time markers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '0:00',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 10,
                  ),
            ),
            Text(
              _formatDuration(story.totalDurationSeconds),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  static String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _TimelineSegment extends StatelessWidget {
  const _TimelineSegment({
    required this.segment,
    required this.index,
    required this.isSelected,
    this.onTap,
  });

  final VideoSegmentModel segment;
  final int index;
  final bool isSelected;
  final VoidCallback? onTap;

  Color _bgColor(ColorScheme colors) => switch (segment.status) {
        SegmentStatus.completed => colors.primary.withValues(alpha: isSelected ? 0.35 : 0.2),
        SegmentStatus.processing => colors.tertiary.withValues(alpha: 0.2),
        SegmentStatus.failed => colors.error.withValues(alpha: 0.2),
        SegmentStatus.pending => colors.surfaceContainerHighest,
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _bgColor(colors),
          border: isSelected
              ? Border.all(color: colors.primary, width: 2)
              : null,
        ),
        child: Center(
          child: segment.isProcessing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.tertiary,
                  ),
                )
              : Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: segment.isCompleted
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                ),
        ),
      ),
    );
  }
}
