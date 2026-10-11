import 'frame.dart';
import 'video_reference_source.dart';

/// Whether a layer's content is a drawing guide (never exported) or
/// genuine artwork (included in the final export, subject to the normal
/// visibility/opacity/ordering rules).
enum LayerType { render, reference }

/// One drawable layer within a shot - its own full sequence of frames,
/// kept the same length as every other layer in the shot. Stacked bottom
/// (layers[0]) to top (layers.last) when composited.
class Layer {
  String id;
  String name;
  bool visible;
  double opacity;
  LayerType type;
  List<AnimFrame> frames;

  /// Only set for a layer created from an imported video snippet - lets the
  /// editor show what the layer was built from and keeps the source footage
  /// associated with it across save/reopen.
  VideoReferenceSource? videoSource;

  Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.type = LayerType.render,
    List<AnimFrame>? frames,
    this.videoSource,
  }) : frames = frames ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'opacity': opacity,
        'type': type.name,
        'frames': frames.map((f) => f.toJson()).toList(),
        'videoSource': videoSource?.toJson(),
      };

  static Layer fromJson(Map<String, dynamic> json) => Layer(
        id: json['id'] as String,
        name: json['name'] as String,
        visible: json['visible'] as bool? ?? true,
        // Older saves have no opacity/type at all - default to fully opaque
        // Render layers, so nothing already exported changes appearance.
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        type: LayerType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => LayerType.render,
        ),
        frames:
            (json['frames'] as List).map((f) => AnimFrame.fromJson(f as Map<String, dynamic>)).toList(),
        videoSource:
            json['videoSource'] != null ? VideoReferenceSource.fromJson(json['videoSource'] as Map<String, dynamic>) : null,
      );
}
