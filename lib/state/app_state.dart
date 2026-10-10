import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/storage_service.dart';
import '../models/achievement.dart';
import '../models/progress.dart';
import '../models/project.dart';

const _uuid = Uuid();

/// Single source of truth for all projects. Holds everything in memory and
/// persists to disk after every change. No backend, no database - just a
/// list of plain objects and a JSON file.
class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<Project> projects = [];
  Progress progress = Progress();
  bool isLoading = true;

  Set<String> get unlockedAchievements => computeUnlockedAchievements(projects, progress.everExported);

  Future<void> load() async {
    final data = await _storage.load();
    projects = data.projects;
    progress = data.progress;
    isLoading = false;
    notifyListeners();
  }

  Future<void> _persist() async {
    await _storage.save(projects, progress);
  }

  Future<void> recordExport(String projectId, String episodeId, String shotId) async {
    final shot = getShot(projectId, episodeId, shotId);
    shot?.exportChecklist.video = true;
    progress.recordActivity(xp: 50, exportedShot: true);
    await _commit();
  }

  Future<void> updateExportChecklist(
    String projectId,
    String episodeId,
    String shotId, {
    bool? audio,
    bool? thumbnail,
    bool? title,
    bool? description,
    bool? subtitles,
  }) async {
    final checklist = getShot(projectId, episodeId, shotId)?.exportChecklist;
    if (checklist == null) return;
    if (audio != null) checklist.audio = audio;
    if (thumbnail != null) checklist.thumbnail = thumbnail;
    if (title != null) checklist.title = title;
    if (description != null) checklist.description = description;
    if (subtitles != null) checklist.subtitles = subtitles;
    await _commit();
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
    if (orientation != null) shot.orientation = orientation;
    if (status != null) _applyShotStatus(projectId, episodeId, shot, status);
    await _commit();
  }

  Future<void> cycleShotStatus(String projectId, String episodeId, String shotId) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return;
    _applyShotStatus(projectId, episodeId, shot, shot.status.next);
    await _commit();
  }

  void _applyShotStatus(String projectId, String episodeId, Shot shot, ShotStatus status) {
    shot.status = status;
    if (status != ShotStatus.complete) return;
    progress.recordActivity(xp: 20, completedShot: true);
    final episode = getEpisode(projectId, episodeId);
    final episodeNowComplete =
        episode != null && episode.shots.isNotEmpty && episode.shots.every((s) => s.status == ShotStatus.complete);
    if (episodeNowComplete) progress.recordActivity(xp: 100);
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
  //
  // Every layer in a shot is kept the same length (see Shot.frameCount), so
  // "frame 5" always means the same point in time across every layer.

  Layer? _findLayer(Shot shot, String layerId) {
    for (final l in shot.layers) {
      if (l.id == layerId) return l;
    }
    return null;
  }

  /// Adds a new frame at the shot's overall timeline position. The active
  /// layer gets a genuinely blank new frame to draw into; every other layer
  /// gets a copy of its own last frame at that position, so (for example) a
  /// background layer doesn't go blank just because you added a frame for
  /// the character layer.
  Future<AnimFrame?> addFrame(
    String projectId,
    String episodeId,
    String shotId, {
    required String activeLayerId,
    int? afterIndex,
  }) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null || shot.layers.isEmpty) return null;
    final insertAt = afterIndex == null ? shot.frameCount : afterIndex + 1;
    AnimFrame? newActiveFrame;
    for (final layer in shot.layers) {
      if (layer.id == activeLayerId) {
        final frame = AnimFrame(id: _uuid.v4());
        layer.frames.insert(insertAt, frame);
        newActiveFrame = frame;
      } else {
        final hasPrevious = insertAt > 0 && insertAt - 1 < layer.frames.length;
        final held = hasPrevious ? layer.frames[insertAt - 1].copy() : AnimFrame(id: _uuid.v4());
        held.id = _uuid.v4();
        layer.frames.insert(insertAt, held);
      }
    }
    progress.recordActivity(xp: 5, addedFrame: true);
    await _commit();
    return newActiveFrame;
  }

  /// Duplicates the frame at [index] across every layer, inserted right
  /// after it.
  Future<int?> duplicateFrame(
    String projectId,
    String episodeId,
    String shotId,
    int index,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null || shot.layers.isEmpty || index < 0 || index >= shot.frameCount) return null;
    for (final layer in shot.layers) {
      final copy = layer.frames[index].copy();
      copy.id = _uuid.v4();
      layer.frames.insert(index + 1, copy);
    }
    progress.recordActivity(xp: 2, addedFrame: true);
    await _commit();
    return index + 1;
  }

  /// Removes the frame at [index] from every layer. Refuses if it's the
  /// shot's only frame.
  Future<void> deleteFrame(
    String projectId,
    String episodeId,
    String shotId,
    int index,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null || shot.frameCount <= 1 || index < 0 || index >= shot.frameCount) return;
    for (final layer in shot.layers) {
      layer.frames.removeAt(index);
    }
    await _commit();
  }

  Future<void> updateFrameStrokes(
    String projectId,
    String episodeId,
    String shotId,
    String layerId,
    int index,
    List<Stroke> strokes,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    final layer = shot == null ? null : _findLayer(shot, layerId);
    if (layer == null || index < 0 || index >= layer.frames.length) return;
    layer.frames[index].strokes = strokes;
    progress.recordActivity(drewFrame: true);
    await _commit();
  }

  // ---- Layers ----

  Future<Layer?> addLayer(
    String projectId,
    String episodeId,
    String shotId, {
    String? name,
  }) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return null;
    final frameCount = shot.frameCount == 0 ? 1 : shot.frameCount;
    final layer = Layer(
      id: _uuid.v4(),
      name: name ?? 'Layer ${shot.layers.length + 1}',
      frames: List.generate(frameCount, (_) => AnimFrame(id: _uuid.v4())),
    );
    shot.layers.add(layer);
    await _commit();
    return layer;
  }

  Future<void> deleteLayer(String projectId, String episodeId, String shotId, String layerId) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null || shot.layers.length <= 1) return;
    shot.layers.removeWhere((l) => l.id == layerId);
    await _commit();
  }

  Future<void> renameLayer(
    String projectId,
    String episodeId,
    String shotId,
    String layerId,
    String name,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    final layer = shot == null ? null : _findLayer(shot, layerId);
    if (layer == null) return;
    layer.name = name;
    await _commit();
  }

  Future<void> toggleLayerVisibility(String projectId, String episodeId, String shotId, String layerId) async {
    final shot = getShot(projectId, episodeId, shotId);
    final layer = shot == null ? null : _findLayer(shot, layerId);
    if (layer == null) return;
    layer.visible = !layer.visible;
    await _commit();
  }

  Future<void> reorderLayers(
    String projectId,
    String episodeId,
    String shotId,
    int oldIndex,
    int newIndex,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final layer = shot.layers.removeAt(oldIndex);
    shot.layers.insert(newIndex, layer);
    await _commit();
  }

  /// Records the drawing canvas's actual pixel size the first time a shot
  /// is opened, so export can later scale strokes (stored in raw screen
  /// coordinates) correctly onto a different target resolution.
  Future<void> recordCanvasSizeIfUnset(
    String projectId,
    String episodeId,
    String shotId,
    double width,
    double height,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null || shot.canvasWidthPx != null) return;
    shot.canvasWidthPx = width;
    shot.canvasHeightPx = height;
    await _commit();
  }

  // ---- Storyboard ----

  Future<void> updateStoryboardStrokes(
    String projectId,
    String episodeId,
    String shotId,
    List<Stroke> strokes,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return;
    shot.storyboardFrame.strokes = strokes;
    await _commit();
  }

  // ---- Camera ----

  Future<void> updateShotCamera(
    String projectId,
    String episodeId,
    String shotId, {
    bool? enabled,
    CameraState? start,
    CameraState? end,
  }) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return;
    if (enabled != null) shot.cameraMoveEnabled = enabled;
    if (start != null) shot.cameraStart = start;
    if (end != null) shot.cameraEnd = end;
    await _commit();
  }

  // ---- Audio ----

  Future<void> setShotAudio(
    String projectId,
    String episodeId,
    String shotId,
    AudioClip clip,
  ) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return;
    shot.audioClip = clip;
    await _commit();
  }

  Future<void> updateShotAudio(
    String projectId,
    String episodeId,
    String shotId, {
    double? trimStart,
    double? trimEnd,
    double? volume,
  }) async {
    final shot = getShot(projectId, episodeId, shotId);
    final clip = shot?.audioClip;
    if (clip == null) return;
    if (trimStart != null) clip.trimStart = trimStart;
    if (trimEnd != null) clip.trimEnd = trimEnd;
    if (volume != null) clip.volume = volume;
    await _commit();
  }

  Future<void> clearShotAudio(String projectId, String episodeId, String shotId) async {
    final shot = getShot(projectId, episodeId, shotId);
    if (shot == null) return;
    shot.audioClip = null;
    await _commit();
  }
}
