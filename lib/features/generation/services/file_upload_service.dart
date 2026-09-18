import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_constants.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/storage_paths.dart';

class UploadedFile {
  const UploadedFile({
    required this.storagePath,
    required this.publicUrl,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  final String storagePath;
  final String publicUrl;
  final String fileName;
  final String mimeType;
  final int fileSize;
}

/// Uploads user-picked files to the `user-uploads` bucket under the current
/// user's namespace, ahead of them being attached to a generation request.
class FileUploadService {
  FileUploadService(this._client);

  final SupabaseClient _client;

  Future<Result<UploadedFile>> uploadUserFile({
    required String userId,
    required File file,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      final path = StoragePaths.upload(userId, fileName);
      await _client.storage.from(AppConstants.storageBucket).upload(
            path,
            file,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      // The bucket is private (see supabase/migrations storage policies), so
      // a signed URL - not getPublicUrl() - is required to read it back.
      // This one is short-lived and good enough to preview/attach to a
      // generation request; screens that need a long-lived link should
      // re-sign from the stored `storagePath` instead of caching this URL.
      final signedUrl = await _client.storage
          .from(AppConstants.storageBucket)
          .createSignedUrl(path, const Duration(hours: 1).inSeconds);
      return Result.success(
        UploadedFile(
          storagePath: path,
          publicUrl: signedUrl,
          fileName: fileName,
          mimeType: mimeType,
          fileSize: await file.length(),
        ),
      );
    } catch (e, st) {
      return Result.failure(ErrorHandler.handle(e, st));
    }
  }
}
