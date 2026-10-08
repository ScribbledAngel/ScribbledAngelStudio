import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/project.dart';

/// Reads and writes every project to a single local JSON file.
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

  Future<List<Project>> loadProjects() async {
    final file = await _dataFile();
    if (!await file.exists()) return [];

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((p) => Project.fromJson(p as Map<String, dynamic>)).toList();
    } catch (_) {
      final backup = File('${file.path}.bak');
      await file.copy(backup.path);
      return [];
    }
  }

  Future<void> saveProjects(List<Project> projects) async {
    final file = await _dataFile();
    final tempFile = File('${file.path}.tmp');
    final json = jsonEncode(projects.map((p) => p.toJson()).toList());
    await tempFile.writeAsString(json, flush: true);
    await tempFile.rename(file.path);
  }
}
