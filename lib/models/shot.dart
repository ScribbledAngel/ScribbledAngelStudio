import 'audio_clip.dart';
import 'camera_state.dart';
import 'frame.dart';

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
class Shot {
  String id;
  String name;
  String notes;
  int fps;
  List<AnimFrame> frames;
  ShotStatus status;
  CanvasOrientation orientation;

  /// A separate, simple sketch used for the storyboard overview - not part
  /// of the animated frames themselves.
  AnimFrame storyboardFrame;

  bool cameraMoveEnabled;
  CameraState cameraStart;
  CameraState cameraEnd;

  AudioClip? audioClip;

  Shot({
    required this.id,
    required this.name,
    this.notes = '',
    this.fps = 12,
    List<AnimFrame>? frames,
    this.status = ShotStatus.notStarted,
    this.orientation = CanvasOrientation.landscape,
    AnimFrame? storyboardFrame,
    this.cameraMoveEnabled = false,
    CameraState? cameraStart,
    CameraState? cameraEnd,
    this.audioClip,
  })  : frames = frames ?? [],
        storyboardFrame = storyboardFrame ?? AnimFrame(id: '$id-storyboard'),
        cameraStart = cameraStart ?? CameraState(),
        cameraEnd = cameraEnd ?? CameraState();

  double get durationSeconds => fps > 0 ? frames.length / fps : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'fps': fps,
        'frames': frames.map((f) => f.toJson()).toList(),
        'status': status.name,
        'orientation': orientation.name,
        'storyboardFrame': storyboardFrame.toJson(),
        'cameraMoveEnabled': cameraMoveEnabled,
        'cameraStart': cameraStart.toJson(),
        'cameraEnd': cameraEnd.toJson(),
        'audioClip': audioClip?.toJson(),
      };

  static Shot fromJson(Map<String, dynamic> json) => Shot(
        id: json['id'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String? ?? '',
        fps: json['fps'] as int? ?? 12,
        frames: (json['frames'] as List)
            .map((f) => AnimFrame.fromJson(f as Map<String, dynamic>))
            .toList(),
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
      );
}
