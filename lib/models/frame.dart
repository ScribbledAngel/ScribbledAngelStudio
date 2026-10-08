import 'stroke.dart';

/// A single drawn frame of animation: just a list of strokes.
class AnimFrame {
  String id;
  List<Stroke> strokes;

  AnimFrame({required this.id, List<Stroke>? strokes}) : strokes = strokes ?? [];

  AnimFrame copy() => AnimFrame(
        id: id,
        strokes: strokes.map((s) => s.copy()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  static AnimFrame fromJson(Map<String, dynamic> json) => AnimFrame(
        id: json['id'] as String,
        strokes: (json['strokes'] as List)
            .map((s) => Stroke.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
