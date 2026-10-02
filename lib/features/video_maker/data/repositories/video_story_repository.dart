import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/utils/result.dart';
import '../models/video_segment_model.dart';
import '../models/video_story_model.dart';

abstract class VideoStoryRepository {
  Future<Result<List<VideoStoryModel>>> getStories(String userId);
  Future<Result<VideoStoryModel>> getStory(String id);
  Future<Result<VideoStoryModel>> createStory(VideoStoryModel story);
  Future<Result<VideoStoryModel>> updateStory(String id, Map<String, dynamic> updates);
  Future<Result<void>> deleteStory(String id);

  Future<Result<VideoSegmentModel>> addSegment(VideoSegmentModel segment);
  Future<Result<VideoSegmentModel>> updateSegment(String id, Map<String, dynamic> updates);
  Future<Result<void>> deleteSegment(String id);
  Future<Result<List<VideoSegmentModel>>> getSegments(String storyId);
  Future<Result<void>> reorderSegments(String storyId, List<String> segmentIds);
}

class SupabaseVideoStoryRepository implements VideoStoryRepository {
  SupabaseVideoStoryRepository(this._client);

  final SupabaseClient _client;
  static const _storiesTable = 'video_stories';
  static const _segmentsTable = 'video_segments';

  @override
  Future<Result<List<VideoStoryModel>>> getStories(String userId) async {
    try {
      final rows = await _client
          .from(_storiesTable)
          .select('*, video_segments(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return Result.success(
        (rows as List).map((r) => VideoStoryModel.fromJson(r)).toList(),
      );
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<VideoStoryModel>> getStory(String id) async {
    try {
      final row = await _client
          .from(_storiesTable)
          .select('*, video_segments(*)')
          .eq('id', id)
          .single();
      return Result.success(VideoStoryModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<VideoStoryModel>> createStory(VideoStoryModel story) async {
    try {
      final row = await _client
          .from(_storiesTable)
          .insert(story.toInsertJson())
          .select('*, video_segments(*)')
          .single();
      return Result.success(VideoStoryModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<VideoStoryModel>> updateStory(
      String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toIso8601String();
      final row = await _client
          .from(_storiesTable)
          .update(updates)
          .eq('id', id)
          .select('*, video_segments(*)')
          .single();
      return Result.success(VideoStoryModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> deleteStory(String id) async {
    try {
      await _client.from(_storiesTable).delete().eq('id', id);
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<VideoSegmentModel>> addSegment(VideoSegmentModel segment) async {
    try {
      final row = await _client
          .from(_segmentsTable)
          .insert(segment.toInsertJson())
          .select()
          .single();
      return Result.success(VideoSegmentModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<VideoSegmentModel>> updateSegment(
      String id, Map<String, dynamic> updates) async {
    try {
      final row = await _client
          .from(_segmentsTable)
          .update(updates)
          .eq('id', id)
          .select()
          .single();
      return Result.success(VideoSegmentModel.fromJson(row));
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> deleteSegment(String id) async {
    try {
      await _client.from(_segmentsTable).delete().eq('id', id);
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<List<VideoSegmentModel>>> getSegments(String storyId) async {
    try {
      final rows = await _client
          .from(_segmentsTable)
          .select()
          .eq('story_id', storyId)
          .order('order_index');
      return Result.success(
        (rows as List).map((r) => VideoSegmentModel.fromJson(r)).toList(),
      );
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<Result<void>> reorderSegments(
      String storyId, List<String> segmentIds) async {
    try {
      for (int i = 0; i < segmentIds.length; i++) {
        await _client
            .from(_segmentsTable)
            .update({'order_index': i})
            .eq('id', segmentIds[i])
            .eq('story_id', storyId);
      }
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
