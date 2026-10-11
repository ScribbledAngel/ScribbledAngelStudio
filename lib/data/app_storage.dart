import 'package:path_provider/path_provider.dart';

/// Caches the app's documents directory path once at startup, so widgets
/// that need to resolve a stored file's full path (reference images, in
/// particular) can do it synchronously during build instead of needing a
/// FutureBuilder everywhere.
class AppStorage {
  static String? _documentsPath;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _documentsPath = dir.path;
  }

  /// The app's documents directory path. Only valid after [init] has been
  /// awaited once, which happens in main() before the app runs.
  static String get documentsPath {
    final path = _documentsPath;
    assert(path != null, 'AppStorage.init() must be awaited before use');
    return path ?? '';
  }
}
