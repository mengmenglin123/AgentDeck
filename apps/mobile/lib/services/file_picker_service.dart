import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Service for picking files and images from the device.
/// Provides a unified interface for file selection across the app.
class FilePickerService {
  FilePickerService._();
  static final instance = FilePickerService._();

  final _imagePicker = ImagePicker();

  /// Pick a single file from the device.
  /// Returns the picked file, or null if cancelled.
  Future<PlatformFile?> pickFile({
    List<String>? allowedExtensions,
    FileType type = FileType.any,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  /// Pick multiple files from the device.
  Future<List<PlatformFile>> pickMultipleFiles({
    List<String>? allowedExtensions,
    FileType type = FileType.any,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return [];
    return result.files;
  }

  /// Pick an image from the gallery.
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    return await _imagePicker.pickImage(source: source, imageQuality: 85);
  }

  /// Take a photo with the camera.
  Future<XFile?> takePhoto() async {
    return await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
  }

  /// Pick a video from the gallery.
  Future<XFile?> pickVideo({ImageSource source = ImageSource.gallery}) async {
    return await _imagePicker.pickVideo(source: source);
  }

  /// Read file bytes for upload.
  Future<List<int>?> readFileBytes(String path) async {
    try {
      final file = File(path);
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
