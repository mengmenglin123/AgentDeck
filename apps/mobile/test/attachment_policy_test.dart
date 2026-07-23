import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/file_picker_service.dart';

void main() {
  test('accepts attachments within item and total limits', () {
    expect(
      () => AttachmentPolicy.validateItem(
        bytes: 1024,
        currentBytes: 2048,
        currentItems: 1,
      ),
      returnsNormally,
    );
  });

  test('rejects oversized item', () {
    expect(
      () => AttachmentPolicy.validateItem(
        bytes: AttachmentPolicy.maxItemBytes + 1,
        currentBytes: 0,
        currentItems: 0,
      ),
      throwsA(isA<AttachmentLimitException>()),
    );
  });

  test('rejects total size and item count overflow', () {
    expect(
      () => AttachmentPolicy.validateItem(
        bytes: 1,
        currentBytes: AttachmentPolicy.maxTotalBytes,
        currentItems: 1,
      ),
      throwsA(isA<AttachmentLimitException>()),
    );
    expect(
      () => AttachmentPolicy.validateItem(
        bytes: 1,
        currentBytes: 0,
        currentItems: AttachmentPolicy.maxItems,
      ),
      throwsA(isA<AttachmentLimitException>()),
    );
  });
}
