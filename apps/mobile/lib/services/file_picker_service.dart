import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class AttachmentLimitException implements Exception {
  AttachmentLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AttachmentPolicy {
  const AttachmentPolicy._();

  static const maxItemBytes = 5 * 1024 * 1024;
  static const maxTotalBytes = 10 * 1024 * 1024;
  static const maxItems = 4;

  static void validateItem({
    required int bytes,
    required int currentBytes,
    required int currentItems,
  }) {
    if (currentItems >= maxItems) {
      throw AttachmentLimitException('最多添加 $maxItems 个附件');
    }
    if (bytes > maxItemBytes) {
      throw AttachmentLimitException('单个附件不能超过 5 MB');
    }
    if (currentBytes + bytes > maxTotalBytes) {
      throw AttachmentLimitException('附件总大小不能超过 10 MB');
    }
  }

  static int bytesIn(Map<String, dynamic> payload) {
    final value = payload['size_bytes'];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }
}

class PickedAttachment {
  PickedAttachment({
    required this.name,
    required this.mime,
    required this.bytes,
  });

  final String name;
  final String mime;
  final List<int> bytes;

  bool get isImage => mime.startsWith('image/');

  Map<String, dynamic> toWire() => {
        'name': name,
        'mime': mime,
        'size_bytes': bytes.length,
        'data_base64': base64Encode(bytes),
      };
}

class FilePickerService {
  FilePickerService._();
  static final instance = FilePickerService._();

  final _imagePicker = ImagePicker();

  Future<PickedAttachment?> pickFile({
    required int currentBytes,
    required int currentItems,
  }) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    AttachmentPolicy.validateItem(
      bytes: file.size,
      currentBytes: currentBytes,
      currentItems: currentItems,
    );
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return null;
    AttachmentPolicy.validateItem(
      bytes: bytes.length,
      currentBytes: currentBytes,
      currentItems: currentItems,
    );
    return PickedAttachment(
      name: file.name,
      mime: _mimeFor(file.name),
      bytes: bytes,
    );
  }

  Future<PickedAttachment?> pickImage({
    required ImageSource source,
    required int currentBytes,
    required int currentItems,
  }) async {
    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (image == null) return null;
    final size = await image.length();
    AttachmentPolicy.validateItem(
      bytes: size,
      currentBytes: currentBytes,
      currentItems: currentItems,
    );
    final bytes = await image.readAsBytes();
    AttachmentPolicy.validateItem(
      bytes: bytes.length,
      currentBytes: currentBytes,
      currentItems: currentItems,
    );
    return PickedAttachment(
      name: image.name,
      mime: _mimeFor(image.name, fallback: 'image/jpeg'),
      bytes: bytes,
    );
  }

  static String _mimeFor(String name,
      {String fallback = 'application/octet-stream'}) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return fallback;
  }
}
