import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/storage_service.dart';
import '../models/project.dart';

const _uuid = Uuid();

/// Single source of truth for all projects. Holds everything in memory and
/// persists to disk after every change. No backend, no database - just a
/// list of plain objects and a JSON file.
class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<Project> projects = [];
  bool isLoading = true;

  Future<void> load() async {
    projects = await _storage.loadProjects();
    isLoading = false;
    notifyListeners();
  }

  Future<void> _persist() async {
    await _storage.saveProjects(projects);
  }

  Future<void> _commit() async {
    notifyListeners();
    await _persist();
  }

  // ---- Lookups ----

  Project? getProject(String projectId) {
    for (final p in projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  Episode? getEpisode(String projectId, String episodeId) {
    final project = getProject(projectId);
    if (project == null) return null;
    for (final e in project.episodes) {
      if (e.id == episodeId) return e;
    }
    return null;
  }

  Shot? getShot(String projectId, String episodeId, String shotId) {
    final episode = getEpisode(projectId, episodeId);
    if (episode == null) return null;
    for (final s in episode.shots) {
      if (s.id == shotId) return s;
    }
    return null;
  }

  // ---- Projects ----

  Future<Project> addProject(String title, String description) async {
    final project = Project(id: _uuid.v4(), title: title, description: description);
    projects.insert(0, project);
    await _commit();
    return project;
  }

  Future<void> updateProject(String projectId, {String? title, String? description}) async {
    final project = getProject(projectId);
    if (project == null) return;
    if (title != null) project.title = title;
    if (description != null) project.description = description;
    await _commit();
  }

  Future<void> deleteProject(String projectId) async {
    projects.removeWhere((p) => p.id == projectId);
    await _commit();
  }

  // ---- Episodes ----

  Future<Episode?> addEpisode(String projectId, String title) async {
    final project = getProject(projectId);
    if (project == null) return null;
    final episode = Episode(id: _uuid.v4(), title: title);
    project.episodes.add(episode);
    await _commit();
    return episode;
  }

  Future<void> deleteEpisode(String projectId, String episodeId) async {
    final project = getProject(projectId);
    if (project == null) return;
    project.episodes.removeWhere((e) => e.id == episodeId);
    await _commit();
  }

  Future<void> reorderEpisodes(String projectId, int oldIndex, int newIndex) async {
    final project = getProject(projectId);
    if (project == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final episode = project.episodes.removeAt(oldIndex);
    project.episodes.insert(newIndex, episode);
    await _commit();
  }

  // ---- Shots ----

  Future<Shot?> addShot(
    String projectId,
    String episodeId, {
    required String name,
    String notes = '',
    int fps = 12,
  }) async {
    final episode = getEpisode(projectId, episodeId);
    if (episode == null) return null;
    final shot = Shot(id: _uuid.v4(), name: name, notes: notes, fps: fps);
    episode.shots.add(shot);
    await _commit();
    return shot;
  }

  Future<void> updateShotMeta(
    String projectId,
    String episodeId,
    String shotId, {
    String? name,
    String? notes,
    int? fps,
    ShotStatus? status,
    CanvasOrientation? orientation,
  }) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return;
    if (name != null) shot.name = name;
    if (notes != null) shot.notes = notes;
    if (fps != null) shot.fps = fps;
    if (status != null) shot.status = status;
    if (orientation != null) shot.orientation = orientation;
    await _commit();
  }

  Future<void> cycleShotStatus(String projectId, String episodeId, String shotId) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return;
    shot.status = shot.status.next;
    await _commit();
  }

  Future<void> deleteShot(String projectId, String episodeId, String shotId) async {
    final episode = getEpisode(projectId, episodeId);
    if (episode == null) return;
    episode.shots.removeWhere((s) => s.id == shotId);
    await _commit();
  }

  Future<void> reorderShots(
    String projectId,
    String episodeId,
    int oldIndex,
    int newIndex,
  ) async {
    final episode = getEpisode(projectId, episodeId);
    if (episode == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final shot = episode.shots.removeAt(oldIndex);
    episode.shots.insert(newIndex, shot);
    await _commit();
  }

  // ---- Frames ----

  Future<AnimFrame?> addFrame(
    String projectId,
    String episodeId,
    String shotId, {
    int? afterIndex,
  }) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return null;
    final frame = AnimFrame(id: _uuid.v4());
    final insertAt = afterIndex == null ? shot.frames.length : afterIndex + 1;
    shot.frames.insert(insertAt, frame);
    await _commit();
    return frame;
  }

  Future<int?> duplicateFrame(
    String projectId,
    String episodeId,
    String shotId,
    int index,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null || index < 0 || index >= shot.frames.length) return null;
    final copy = shot.frames[index].copy();
    copy.id = _uuid.v4();
    shot.frames.insert(index + 1, copy);
    await _commit();
    return index + 1;
  }

  Future<void> deleteFrame(
    String projectId,
    String episodeId,
    String shotId,
    int index,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null || index < 0 || index >= shot.frames.length) return;
    shot.frames.removeAt(index);
    await _commit();
  }

  Future<void> updateFrameStrokes(
    String projectId,
    String episodeId,
    String shotId,
    int index,
    List<Stroke> strokes,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null || index < 0 || index >= shot.frames.length) return;
    shot.frames[index].strokes = strokes;
    await _commit();
  }
}
