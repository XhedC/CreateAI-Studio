import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'app_error_widget.dart';
import 'loading_widget.dart';

/// Reusable video player: play/pause, seek, progress, duration, fullscreen,
/// mute/unmute, loading and error states - built on the maintained
/// `video_player` + `chewie` packages rather than hand-rolled controls.
/// Preserves the video's own aspect ratio (portrait or landscape) instead
/// of stretching it to fill the available width.
class VideoPlayerWidget extends StatefulWidget {
  const VideoPlayerWidget({super.key, required this.url});

  final String url;

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        aspectRatio: controller.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
        ),
      );
      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _isLoading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Unable to play this video. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: AppErrorWidget(message: _error!),
      );
    }
    if (_isLoading || _chewieController == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: LoadingWidget(),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Chewie(controller: _chewieController!),
      ),
    );
  }
}
