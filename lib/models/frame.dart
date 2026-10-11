import 'stroke.dart';

/// A single drawn frame of animation: a list of strokes, plus an optional
/// reference/background image (used by image and video reference layers -
/// a still image repeats the same path on every frame, a video reference
/// has a different extracted-frame path per frame).
class AnimFrame {
  String id;
  List<Stroke> strokes;
  String? imagePath;

  AnimFrame({required this.id, List<Stroke>? strokes, this.imagePath}) : strokes = strokes ?? [];

  AnimFrame copy() => AnimFrame(
        id: id,
        strokes: strokes.map((s) => s.copy()).toList(),
        imagePath: imagePath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'imagePath': imagePath,
      };

  static AnimFrame fromJson(Map<String, dynamic> json) => AnimFrame(
        id: json['id'] as String,
        strokes: (json['strokes'] as List)
            .map((s) => Stroke.fromJson(s as Map<String, dynamic>))
            .toList(),
        imagePath: json['imagePath'] as String?,
      );
}
