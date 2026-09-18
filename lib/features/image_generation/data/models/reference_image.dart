import 'dart:io';

import 'package:equatable/equatable.dart';

/// A reference image the user picked (camera or gallery) but has not
/// necessarily uploaded yet. Kept separate from [UploadedFile]
/// (features/generation/services/file_upload_service.dart), which
/// represents the post-upload result - this is the pre-upload,
/// UI-facing selection.
class ReferenceImage extends Equatable {
  const ReferenceImage({
    required this.file,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
  });

  final File file;
  final String fileName;
  final String mimeType;
  final int fileSizeBytes;

  @override
  List<Object?> get props => [file.path, fileName, mimeType, fileSizeBytes];
}
