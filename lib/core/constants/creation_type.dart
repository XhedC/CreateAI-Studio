import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The kinds of AI creation this app supports. This is the single place that
/// enumerates categories - adding a new AI feature (e.g. voice, logo) means
/// adding one entry here plus one [AIProvider] implementation; no other file
/// needs to change its structure.
enum CreationType {
  text('text', 'AI Chat', Icons.chat_bubble_outline_rounded, AppColors.textType),
  image('image', 'AI Image', Icons.image_outlined, AppColors.imageType),
  music('music', 'AI Music', Icons.music_note_outlined, AppColors.musicType),
  video('video', 'AI Video', Icons.videocam_outlined, AppColors.videoType),
  funnel('funnel', 'AI Funnel', Icons.web_outlined, AppColors.funnelType);

  const CreationType(this.value, this.label, this.icon, this.color);

  /// Stored value in the database (`generations.generation_type`,
  /// `projects.project_type`).
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  static CreationType fromValue(String value) => CreationType.values.firstWhere(
        (t) => t.value == value,
        orElse: () => CreationType.text,
      );

  /// All categories run through the mocked generation pipeline in Phase 1
  /// (no paid AI API calls) so the end-to-end architecture - prompt, upload,
  /// generation record, history, project linkage - can be exercised for
  /// every type before a real [AIProvider] is plugged in.
  bool get isAvailable => true;
}
