import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import 'app_storage.dart';

const _uuid = Uuid();

/// Manages still reference images copied into the app's private storage
/// (so the original picked file can move/disappear without breaking the
/// layer). Video reference files are handled separately, once that part of
/// the rotoscoping workflow is built.
class ReferenceAssetService {
  Future<Directory> ensureImagesDir() async {
    final dir = Directory('${AppStorage.documentsPath}/reference_images');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String fullPathFor(String fileName) => '${AppStorage.documentsPath}/reference_images/$fileName';

  /// Lets the user pick an image from device storage, copies it into the
  /// app's private folder, and returns the new file's bare name.
  Future<String?> importImage() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    final pickedPath = picked?.path;
    if (pickedPath == null) return null;

    final extension = pickedPath.contains('.') ? pickedPath.split('.').last : 'png';
    final fileName = '${_uuid.v4()}.$extension';
    final dir = await ensureImagesDir();
    await File(pickedPath).copy('${dir.path}/$fileName');
    return fileName;
  }

  Future<void> deleteImage(String fileName) async {
    final file = File(fullPathFor(fileName));
    if (await file.exists()) await file.delete();
  }
}
