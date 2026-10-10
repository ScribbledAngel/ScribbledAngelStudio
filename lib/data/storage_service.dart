import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/progress.dart';
import '../models/project.dart';

/// Everything loaded from, or written to, the single local data file.
class AppData {
  final List<Project> projects;
  final Progress progress;

  AppData({required this.projects, required this.progress});
}

/// Reads and writes all app data to a single local JSON file.
///
/// Writes are atomic (write to a temp file, then replace) so a crash or a
/// low-battery shutdown mid-save can't corrupt your drawings. If the saved
/// file is ever unreadable, it's preserved as a `.bak` instead of being
/// silently overwritten, so nothing is lost without a trace.
class StorageService {
  static const _fileName = 'scribbled_angel_studio_data.json';

  Future<File> _dataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<AppData> load() async {
    final file = await _dataFile();
    if (!await file.exists()) return AppData(projects: [], progress: Progress());

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return AppData(projects: [], progress: Progress());

    try {
      final decoded = jsonDecode(raw);
      // Older save files were a bare JSON array of projects, with no
      // progress data yet - keep loading those instead of discarding them.
      if (decoded is List) {
        return AppData(
          projects: decoded.map((p) => Project.fromJson(p as Map<String, dynamic>)).toList(),
          progress: Progress(),
        );
      }
      final map = decoded as Map<String, dynamic>;
      final projects = (map['projects'] as List? ?? [])
          .map((p) => Project.fromJson(p as Map<String, dynamic>))
          .toList();
      final progress =
          map['progress'] != null ? Progress.fromJson(map['progress'] as Map<String, dynamic>) : Progress();
      return AppData(projects: projects, progress: progress);
    } catch (_) {
      final backup = File('${file.path}.bak');
      await file.copy(backup.path);
      return AppData(projects: [], progress: Progress());
    }
  }

  Future<void> save(List<Project> projects, Progress progress) async {
    final file = await _dataFile();
    final tempFile = File('${file.path}.tmp');
    final json = jsonEncode({
      'projects': projects.map((p) => p.toJson()).toList(),
      'progress': progress.toJson(),
    });
    await tempFile.writeAsString(json, flush: true);
    await tempFile.rename(file.path);
  }
}
