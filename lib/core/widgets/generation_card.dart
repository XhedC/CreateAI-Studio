import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/creation_type.dart';
import '../constants/generation_status.dart';
import '../utils/date_formatter.dart';

class GenerationCard extends StatelessWidget {
  const GenerationCard({
    super.key,
    required this.prompt,
    required this.generationType,
    required this.status,
    required this.createdAt,
    this.thumbnailUrl,
    this.onTap,
  });

  final String prompt;
  final String generationType;
  final String status;
  final DateTime createdAt;

  /// When present (e.g. a completed image generation), shown instead of the
  /// generic category icon.
  final String? thumbnailUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = CreationType.fromValue(generationType);
    final genStatus = GenerationStatus.fromValue(status);
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: thumbnailUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => _iconFallback(type),
                        errorWidget: (context, url, error) => _iconFallback(type),
                      )
                    : _iconFallback(type),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(genStatus.icon, size: 14, color: genStatus.color),
                        const SizedBox(width: 4),
                        Text(
                          genStatus.label,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: genStatus.color),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          DateFormatter.relative(createdAt),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconFallback(CreationType type) {
    return Container(
      width: 40,
      height: 40,
      color: type.color.withValues(alpha: 0.12),
      child: Icon(type.icon, color: type.color, size: 20),
    );
  }
}
