import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/widgets/video_player_widget.dart';

void main() {
  testWidgets('shows a loading indicator before the video has initialized', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoPlayerWidget(url: 'https://example.com/video.mp4'),
        ),
      ),
    );

    // No platform video plugin is registered in a plain widget test, so the
    // underlying controller.initialize() call never resolves here - this
    // only verifies the widget's synchronous initial loading state (set in
    // initState, before the async gap), not pumpAndSettle-to-completion,
    // which would depend on a platform channel with no handler. Mirrors
    // audio_player_widget_test.dart's approach from Phase 3.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
