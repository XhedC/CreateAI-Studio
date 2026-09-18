import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/features/image_generation/data/models/reference_image.dart';
import 'package:createai_studio/features/image_generation/services/reference_image_validator.dart';

ReferenceImage _image({
  String mimeType = 'image/png',
  int fileSizeBytes = 1024,
}) {
  return ReferenceImage(
    file: File('unused.png'),
    fileName: 'unused.png',
    mimeType: mimeType,
    fileSizeBytes: fileSizeBytes,
  );
}

void main() {
  group('ReferenceImageValidator', () {
    test('accepts JPEG, PNG and WEBP', () {
      expect(ReferenceImageValidator.validate(_image(mimeType: 'image/jpeg')), isNull);
      expect(ReferenceImageValidator.validate(_image(mimeType: 'image/png')), isNull);
      expect(ReferenceImageValidator.validate(_image(mimeType: 'image/webp')), isNull);
    });

    test('rejects an unsupported format', () {
      final error = ReferenceImageValidator.validate(_image(mimeType: 'image/gif'));
      expect(error, 'Unsupported image format.');
    });

    test('rejects a file over the size limit', () {
      final error = ReferenceImageValidator.validate(
        _image(fileSizeBytes: ReferenceImageValidator.maxFileSizeBytes + 1),
      );
      expect(error, 'Image is too large.');
    });

    test('accepts a file exactly at the size limit', () {
      final error = ReferenceImageValidator.validate(
        _image(fileSizeBytes: ReferenceImageValidator.maxFileSizeBytes),
      );
      expect(error, isNull);
    });

    test('rejects an empty (zero-byte) file', () {
      final error = ReferenceImageValidator.validate(_image(fileSizeBytes: 0));
      expect(error, isNotNull);
    });
  });
}
