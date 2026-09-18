import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../services/file_upload_service.dart';
import '../providers/generation_providers.dart';

/// Upload button + attached-file chips, reused by the Create screen for any
/// creation type. Uploads go straight to Supabase Storage so the resulting
/// public URLs can be forwarded to an [AIProvider] as reference material.
class UploadAttachmentsField extends ConsumerStatefulWidget {
  const UploadAttachmentsField({super.key, required this.onChanged});

  final ValueChanged<List<UploadedFile>> onChanged;

  @override
  ConsumerState<UploadAttachmentsField> createState() =>
      _UploadAttachmentsFieldState();
}

class _UploadAttachmentsFieldState extends ConsumerState<UploadAttachmentsField> {
  final List<UploadedFile> _files = [];
  bool _isUploading = false;

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.pickFiles(withData: false);
    final path = picked?.files.single.path;
    if (path == null) return;

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    setState(() => _isUploading = true);
    final service = ref.read(fileUploadServiceProvider);
    final file = File(path);
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${picked!.files.single.name}';

    final result = await service.uploadUserFile(
      userId: user.id,
      file: file,
      fileName: fileName,
      mimeType: _mimeTypeFor(picked.files.single.extension),
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    result.when(
      success: (uploaded) {
        setState(() => _files.add(uploaded));
        widget.onChanged(_files);
      },
      failure: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      },
    );
  }

  String _mimeTypeFor(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'mp3':
        return 'audio/mpeg';
      case 'mp4':
        return 'video/mp4';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  void _remove(UploadedFile file) {
    setState(() => _files.remove(file));
    widget.onChanged(_files);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _isUploading ? null : _pickAndUpload,
          icon: _isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.attach_file_rounded),
          label: Text(_isUploading ? 'Uploading...' : 'Upload a file'),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final file in _files)
                Chip(
                  label: Text(
                    file.fileName,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onDeleted: () => _remove(file),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
