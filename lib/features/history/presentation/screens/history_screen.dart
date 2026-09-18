import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/creation_type.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/generation_card.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../generation/presentation/providers/generation_providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generationsAsync = ref.watch(generationsProvider);
    final filters = ref.watch(historyFiltersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search prompts...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) =>
                  ref.read(historyFiltersProvider.notifier).setSearchQuery(value),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: filters.type == null,
                    onSelected: (_) =>
                        ref.read(historyFiltersProvider.notifier).setType(null),
                  ),
                ),
                for (final type in CreationType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(type.label),
                      selected: filters.type == type,
                      onSelected: (_) =>
                          ref.read(historyFiltersProvider.notifier).setType(type),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: generationsAsync.when(
              loading: () => const LoadingWidget(),
              error: (_, __) => AppErrorWidget(
                onRetry: () => ref.invalidate(generationsProvider),
              ),
              data: (generations) {
                if (generations.isEmpty) {
                  return const EmptyState(
                    icon: Icons.history_rounded,
                    title: 'No generations yet',
                    message: 'Your AI creations will show up here once you make one.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: generations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final generation = generations[index];
                    return GenerationCard(
                      prompt: generation.prompt,
                      generationType: generation.generationType,
                      status: generation.status,
                      createdAt: generation.createdAt,
                      thumbnailUrl: generation.thumbnailUrl,
                      onTap: () =>
                          context.push(RoutePaths.generationDetail(generation.id)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
