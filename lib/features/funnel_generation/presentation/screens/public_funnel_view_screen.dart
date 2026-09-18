import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/funnel_providers.dart';
import '../widgets/funnel_renderer.dart';

/// The public, unauthenticated view of a published funnel - reachable at
/// `/f/:slug` without signing in (see app_router.dart's `redirect`
/// exception for this one path). This is the ONLY screen in the app that
/// renders [FunnelRenderer] with [FunnelRenderer.publicSlug] set, i.e. the
/// only place the public lead-form submission path is ever used.
///
/// Also doubles as the in-app "Preview Published Version" destination for
/// the owner (from the Funnel Editor / [PublishStatusCard]) - it is
/// intentionally the exact same screen a real visitor would see, so
/// "preview" never lies about what's actually public. See
/// docs/PHASE_7_PUBLISHING.md "Public preview".
class PublicFunnelViewScreen extends ConsumerWidget {
  const PublicFunnelViewScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final funnelAsync = ref.watch(publicFunnelProvider(slug));
    // A signed-in viewer is almost certainly the owner previewing, not a
    // real anonymous visitor - show a small banner distinguishing this
    // from the editor's own live-draft preview (section 11 of the brief).
    final isSignedIn = ref.watch(authStateProvider).value != null;

    return Scaffold(
      appBar: isSignedIn
          ? AppBar(
              title: const Text('Published Funnel'),
              leading: context.canPop()
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => context.pop(),
                    )
                  : null,
            )
          : null,
      body: SafeArea(
        child: funnelAsync.when(
          loading: () => const LoadingWidget(),
          error: (_, __) => AppErrorWidget(
            message: 'Something went wrong loading this page. Please try again.',
            onRetry: () => ref.invalidate(publicFunnelProvider(slug)),
          ),
          data: (view) {
            if (view == null) {
              return const EmptyState(
                icon: Icons.link_off_rounded,
                title: 'Funnel not found',
                message: 'This page may have been unpublished, or the link may be incorrect.',
              );
            }
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                if (isSignedIn)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.primaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      'PUBLIC PUBLISHED VERSION - this is exactly what visitors see.',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                FunnelRenderer(
                  schema: view.content,
                  publicSlug: slug,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
