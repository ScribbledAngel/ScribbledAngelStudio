import 'frame.dart';

/// One drawable layer within a shot - its own full sequence of frames,
/// kept the same length as every other layer in the shot. Stacked bottom
/// (layers[0]) to top (layers.last) when composited.
class Layer {
  String id;
  String name;
  bool visible;
  List<AnimFrame> frames;

  Layer({
    required this.id,
    required this.name,
    this.visible = true,
    List<AnimFrame>? frames,
  }) : frames = frames ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'frames': frames.map((f) => f.toJson()).toList(),
      };

  static Layer fromJson(Map<String, dynamic> json) => Layer(
        id: json['id'] as String,
        name: json['name'] as String,
        visible: json['visible'] as bool? ?? true,
        frames:
            (json['frames'] as List).map((f) => AnimFrame.fromJson(f as Map<String, dynamic>)).toList(),
      );
}
