import 'audio_clip.dart';
import 'camera_state.dart';
import 'export_checklist.dart';
import 'frame.dart';
import 'layer.dart';
import 'layer_frame_content.dart';
import 'stroke.dart';

enum ShotStatus { notStarted, inProgress, complete }

/// The shape of the shot's canvas: widescreen (16:9, for YouTube) or
/// vertical (9:16, for Shorts/TikTok-style).
enum CanvasOrientation { landscape, portrait }

extension CanvasOrientationX on CanvasOrientation {
  double get aspectRatio => this == CanvasOrientation.landscape ? 16 / 9 : 9 / 16;
}

extension ShotStatusX on ShotStatus {
  String get label {
    switch (this) {
      case ShotStatus.notStarted:
        return 'Not started';
      case ShotStatus.inProgress:
        return 'In progress';
      case ShotStatus.complete:
        return 'Complete';
    }
  }

  ShotStatus get next {
    switch (this) {
      case ShotStatus.notStarted:
        return ShotStatus.inProgress;
      case ShotStatus.inProgress:
        return ShotStatus.complete;
      case ShotStatus.complete:
        return ShotStatus.notStarted;
    }
  }

  int get completionPercent {
    switch (this) {
      case ShotStatus.notStarted:
        return 0;
      case ShotStatus.inProgress:
        return 50;
      case ShotStatus.complete:
        return 100;
    }
  }
}

/// A single shot within an episode, e.g. "001 Cold Open".
///
/// Frames live inside [layers] now, not directly on the shot - every layer
/// is kept the same length (see [frameCount]), so "frame 5" always means
/// the same point in time across every layer.
class Shot {
  String id;
  String name;
  String notes;
  int fps;
  List<Layer> layers;
  ShotStatus status;
  CanvasOrientation orientation;

  /// A separate, simple sketch used for the storyboard overview - not part
  /// of the animated frames themselves, and not layered.
  AnimFrame storyboardFrame;

  bool cameraMoveEnabled;
  CameraState cameraStart;
  CameraState cameraEnd;

  AudioClip? audioClip;

  /// The pixel size the drawing canvas was actually rendered at when this
  /// shot's strokes were recorded (strokes are stored in raw screen
  /// coordinates, not normalized 0-1 fractions). Export needs this to scale
  /// the artwork correctly onto a different target resolution. Set once,
  /// the first time a stroke is drawn.
  double? canvasWidthPx;
  double? canvasHeightPx;

  ExportChecklist exportChecklist;

  Shot({
    required this.id,
    required this.name,
    this.notes = '',
    this.fps = 12,
    List<Layer>? layers,
    this.status = ShotStatus.notStarted,
    this.orientation = CanvasOrientation.landscape,
    AnimFrame? storyboardFrame,
    this.cameraMoveEnabled = false,
    CameraState? cameraStart,
    CameraState? cameraEnd,
    this.audioClip,
    this.canvasWidthPx,
    this.canvasHeightPx,
    ExportChecklist? exportChecklist,
  })  : layers = layers ?? [Layer(id: '$id-layer-1', name: 'Layer 1')],
        storyboardFrame = storyboardFrame ?? AnimFrame(id: '$id-storyboard'),
        cameraStart = cameraStart ?? CameraState(),
        cameraEnd = cameraEnd ?? CameraState(),
        exportChecklist = exportChecklist ?? ExportChecklist();

  /// The shot's overall timeline length - every layer is kept this long.
  int get frameCount => layers.isEmpty ? 0 : layers.first.frames.length;

  double get durationSeconds => fps > 0 ? frameCount / fps : 0;

  /// All visible layers' strokes at [index], bottom layer first, merged
  /// into one paint order - what the composed frame actually looks like.
  List<Stroke> compositeStrokesAt(int index) {
    final merged = <Stroke>[];
    for (final layer in layers) {
      if (!layer.visible) continue;
      if (index < 0 || index >= layer.frames.length) continue;
      merged.addAll(layer.frames[index].strokes);
    }
    return merged;
  }

  bool get hasAnyStrokes => layers.any((l) => l.frames.any((f) => f.strokes.isNotEmpty));

  /// Every visible layer's content at [index] (reference layers included) -
  /// used by the live editor, onion skin and thumbnails, where seeing a
  /// drawing guide is the whole point.
  List<LayerFrameContent> editorLayerContentsAt(int index, {String? excludeLayerId}) {
    final result = <LayerFrameContent>[];
    for (final layer in layers) {
      if (layer.id == excludeLayerId) continue;
      if (!layer.visible || index < 0 || index >= layer.frames.length) continue;
      final frame = layer.frames[index];
      result.add(LayerFrameContent(strokes: frame.strokes, imagePath: frame.imagePath, opacity: layer.opacity));
    }
    return result;
  }

  /// Only visible Render-type layers' content at [index] - what actually
  /// goes into the exported video. Reference layers never appear here,
  /// regardless of their editor visibility.
  List<LayerFrameContent> exportLayerContentsAt(int index) {
    final result = <LayerFrameContent>[];
    for (final layer in layers) {
      if (layer.type != LayerType.render || !layer.visible) continue;
      if (index < 0 || index >= layer.frames.length) continue;
      final frame = layer.frames[index];
      result.add(LayerFrameContent(strokes: frame.strokes, imagePath: frame.imagePath, opacity: layer.opacity));
    }
    return result;
  }

  /// Whether there's anything a Render layer would actually put on screen -
  /// used to warn before producing a silently blank export.
  bool get hasExportableContent => layers.any(
        (l) =>
            l.type == LayerType.render &&
            l.frames.any((f) => f.strokes.isNotEmpty || f.imagePath != null),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'fps': fps,
        'layers': layers.map((l) => l.toJson()).toList(),
        'status': status.name,
        'orientation': orientation.name,
        'storyboardFrame': storyboardFrame.toJson(),
        'cameraMoveEnabled': cameraMoveEnabled,
        'cameraStart': cameraStart.toJson(),
        'cameraEnd': cameraEnd.toJson(),
        'audioClip': audioClip?.toJson(),
        'canvasWidthPx': canvasWidthPx,
        'canvasHeightPx': canvasHeightPx,
        'exportChecklist': exportChecklist.toJson(),
      };

  static Shot fromJson(Map<String, dynamic> json) => Shot(
        id: json['id'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String? ?? '',
        fps: json['fps'] as int? ?? 12,
        layers: _layersFromJson(json),
        status: ShotStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => ShotStatus.notStarted,
        ),
        orientation: CanvasOrientation.values.firstWhere(
          (o) => o.name == json['orientation'],
          orElse: () => CanvasOrientation.landscape,
        ),
        storyboardFrame: json['storyboardFrame'] != null
            ? AnimFrame.fromJson(json['storyboardFrame'] as Map<String, dynamic>)
            : null,
        cameraMoveEnabled: json['cameraMoveEnabled'] as bool? ?? false,
        cameraStart: json['cameraStart'] != null
            ? CameraState.fromJson(json['cameraStart'] as Map<String, dynamic>)
            : null,
        cameraEnd: json['cameraEnd'] != null
            ? CameraState.fromJson(json['cameraEnd'] as Map<String, dynamic>)
            : null,
        audioClip: json['audioClip'] != null
            ? AudioClip.fromJson(json['audioClip'] as Map<String, dynamic>)
            : null,
        canvasWidthPx: (json['canvasWidthPx'] as num?)?.toDouble(),
        canvasHeightPx: (json['canvasHeightPx'] as num?)?.toDouble(),
        exportChecklist: json['exportChecklist'] != null
            ? ExportChecklist.fromJson(json['exportChecklist'] as Map<String, dynamic>)
            : null,
      );

  /// Reads `layers` when present; otherwise migrates an older save file's
  /// flat `frames` list into a single default layer, so nothing drawn
  /// before this feature existed is lost.
  static List<Layer>? _layersFromJson(Map<String, dynamic> json) {
    if (json['layers'] != null) {
      return (json['layers'] as List).map((l) => Layer.fromJson(l as Map<String, dynamic>)).toList();
    }
    if (json['frames'] != null) {
      final frames =
          (json['frames'] as List).map((f) => AnimFrame.fromJson(f as Map<String, dynamic>)).toList();
      return [Layer(id: '${json['id']}-layer-1', name: 'Layer 1', frames: frames)];
    }
    return null;
  }
}
