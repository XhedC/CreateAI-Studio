import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/widgets/audio_player_widget.dart';

void main() {
  testWidgets('renders the initial paused state with a play button', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AudioPlayerWidget(
              generationId: 'gen-1',
              title: 'My Song',
              url: 'https://example.com/song.mp3',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.play_circle_filled_rounded), findsOneWidget);
    expect(find.text('My Song'), findsOneWidget);
  });

  testWidgets('shows a loading spinner immediately after tapping play', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AudioPlayerWidget(
              generationId: 'gen-1',
              title: 'My Song',
              url: 'https://example.com/song.mp3',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // No platform audio plugin is registered in a plain widget test, so the
    // underlying play() call never resolves here - this only verifies the
    // widget's own synchronous loading-state transition (setState happens
    // before the async gap), not pumpAndSettle-to-completion, which would
    // hang waiting on a platform channel that has no handler.
    await tester.tap(find.byIcon(Icons.play_circle_filled_rounded));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_filled_rounded), findsNothing);
  });
}
