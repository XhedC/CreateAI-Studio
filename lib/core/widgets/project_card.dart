import 'package:flutter/material.dart';

import '../constants/creation_type.dart';
import '../utils/date_formatter.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.name,
    required this.projectType,
    required this.updatedAt,
    this.description,
    this.thumbnailUrl,
    this.onTap,
    this.onMorePressed,
  });

  final String name;
  final String projectType;
  final DateTime updatedAt;
  final String? description;
  final String? thumbnailUrl;
  final VoidCallback? onTap;
  final VoidCallback? onMorePressed;

  @override
  Widget build(BuildContext context) {
    final type = CreationType.fromValue(projectType);
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(type.icon, color: type.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Updated ${DateFormatter.relative(updatedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (onMorePressed != null)
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: onMorePressed,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
