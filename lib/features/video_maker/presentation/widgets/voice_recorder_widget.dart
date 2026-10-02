import 'dart:async';

import 'package:flutter/material.dart';

class VoiceRecorderWidget extends StatefulWidget {
  const VoiceRecorderWidget({
    super.key,
    required this.onRecordingComplete,
    this.enabled = true,
  });

  final ValueChanged<String?> onRecordingComplete;
  final bool enabled;

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });
    _pulseController.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= 120) _stopRecording();
    });
  }

  void _stopRecording() {
    _timer?.cancel();
    _pulseController.stop();
    setState(() => _isRecording = false);
    // In production, this would return the actual recorded audio file path.
    // For now we pass a placeholder path that the generation pipeline handles.
    widget.onRecordingComplete(
      'voice_recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
  }

  void _cancelRecording() {
    _timer?.cancel();
    _pulseController.stop();
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
    });
    widget.onRecordingComplete(null);
  }

  String get _formattedDuration {
    final minutes = _recordingSeconds ~/ 60;
    final seconds = _recordingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_isRecording) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 64 + (_pulseController.value * 12),
                  height: 64 + (_pulseController.value * 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.error.withValues(
                      alpha: 0.15 + (_pulseController.value * 0.1),
                    ),
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    size: 32,
                    color: colors.error,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              _formattedDuration,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Recording your narration...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _cancelRecording,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: widget.enabled ? _startRecording : null,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.outlineVariant,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryContainer,
              ),
              child: Icon(
                Icons.mic_rounded,
                size: 32,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap to Record',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Describe your video scene with your voice.\nThe AI will create visuals matching your narration.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
