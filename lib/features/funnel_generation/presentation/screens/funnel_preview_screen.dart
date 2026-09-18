import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../providers/funnel_providers.dart';
import '../widgets/funnel_renderer.dart';

enum _PreviewDevice { mobile, tablet, desktop }

/// Responsive funnel preview: the SAME [FunnelSchema] and the SAME
/// [FunnelRenderer] are used for every device mode - only the surrounding
/// max-width constraint changes, per the brief ("do not create separate
/// hard-coded layouts for every device").
class FunnelPreviewScreen extends ConsumerStatefulWidget {
  const FunnelPreviewScreen({super.key, required this.funnelId});

  final String funnelId;

  @override
  ConsumerState<FunnelPreviewScreen> createState() => _FunnelPreviewScreenState();
}

class _FunnelPreviewScreenState extends ConsumerState<FunnelPreviewScreen> {
  _PreviewDevice _device = _PreviewDevice.mobile;

  double _widthFor(_PreviewDevice device) => switch (device) {
        _PreviewDevice.mobile => 390,
        _PreviewDevice.tablet => 768,
        _PreviewDevice.desktop => double.infinity,
      };

  @override
  Widget build(BuildContext context) {
    // Reads the SAME live-edited state the Funnel Editor holds, so a
    // preview reflects unsaved changes without a second network read.
    final funnelAsync = ref.watch(funnelEditorProvider(widget.funnelId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: SegmentedButton<_PreviewDevice>(
                segments: const [
                  ButtonSegment(
                    value: _PreviewDevice.mobile,
                    icon: Icon(Icons.smartphone_rounded),
                    label: Text('Mobile'),
                  ),
                  ButtonSegment(
                    value: _PreviewDevice.tablet,
                    icon: Icon(Icons.tablet_mac_rounded),
                    label: Text('Tablet'),
                  ),
                  ButtonSegment(
                    value: _PreviewDevice.desktop,
                    icon: Icon(Icons.desktop_windows_rounded),
                    label: Text('Desktop'),
                  ),
                ],
                selected: {_device},
                onSelectionChanged: (selection) => setState(() => _device = selection.first),
              ),
            ),
          ),
        ),
      ),
      body: funnelAsync.when(
        loading: () => const LoadingWidget(),
        error: (_, __) => const AppErrorWidget(),
        data: (funnel) => Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _widthFor(_device)),
              child: SingleChildScrollView(
                child: FunnelRenderer(schema: funnel.content, funnelId: funnel.id),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
