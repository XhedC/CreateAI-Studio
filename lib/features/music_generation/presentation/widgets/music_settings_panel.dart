import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/music_generation_settings.dart';
import '../providers/music_generation_providers.dart';

/// The expandable "Music Settings" section. Collapsed by default with
/// sensible defaults already applied, so the screen stays simple for anyone
/// who just wants to type a prompt and generate.
class MusicSettingsPanel extends ConsumerStatefulWidget {
  const MusicSettingsPanel({super.key});

  @override
  ConsumerState<MusicSettingsPanel> createState() => _MusicSettingsPanelState();
}

class _MusicSettingsPanelState extends ConsumerState<MusicSettingsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(musicSettingsProvider);
    final notifier = ref.read(musicSettingsProvider.notifier);

    return ExpansionTile(
      title: const Text('Music Settings'),
      initiallyExpanded: _expanded,
      onExpansionChanged: (v) => setState(() => _expanded = v),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      children: [
        _SectionLabel('Genre'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final genre in MusicGenre.values)
              ChoiceChip(
                label: Text(genre.label),
                selected: settings.genre == genre,
                onSelected: (_) => notifier.setGenre(genre),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Mood'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mood in MusicMood.values)
              ChoiceChip(
                label: Text(mood.label),
                selected: settings.mood == mood,
                onSelected: (_) => notifier.setMood(mood),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Vocals'),
        SegmentedButton<MusicVocalType>(
          segments: [
            for (final vocal in MusicVocalType.values)
              ButtonSegment(value: vocal, label: Text(vocal.label)),
          ],
          selected: {settings.vocalType},
          onSelectionChanged: (selection) => notifier.setVocalType(selection.first),
        ),
        const SizedBox(height: 16),
        _SectionLabel('Language'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final language in MusicLanguage.values)
              ChoiceChip(
                label: Text(language.label),
                selected: settings.language == language,
                onSelected: (_) => notifier.setLanguage(language),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Duration'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final duration in MusicDuration.values)
              ChoiceChip(
                label: Text('${duration.label} (${duration.approxLength})'),
                selected: settings.duration == duration,
                onSelected: (_) => notifier.setDuration(duration),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionLabel('Tempo'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tempo in MusicTempo.values)
              ChoiceChip(
                label: Text(tempo.label),
                selected: settings.tempo == tempo,
                onSelected: (_) => notifier.setTempo(tempo),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
