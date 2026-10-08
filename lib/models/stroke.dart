import 'dart:ui';

/// A single drawn stroke: a sequence of points with a color, width and
/// whether it erases (clears) instead of paints.
class Stroke {
  String id;
  int colorValue;
  double width;
  bool isEraser;
  List<Offset> points;

  Stroke({
    required this.id,
    required this.colorValue,
    required this.width,
    required this.isEraser,
    List<Offset>? points,
  }) : points = points ?? [];

  Color get color => Color(colorValue);

  Stroke copy() => Stroke(
        id: id,
        colorValue: colorValue,
        width: width,
        isEraser: isEraser,
        points: List<Offset>.from(points),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'color': colorValue,
        'width': width,
        'eraser': isEraser,
        'points': points.map((p) => [p.dx, p.dy]).toList(),
      };

  static Stroke fromJson(Map<String, dynamic> json) => Stroke(
        id: json['id'] as String,
        colorValue: json['color'] as int,
        width: (json['width'] as num).toDouble(),
        isEraser: json['eraser'] as bool? ?? false,
        points: (json['points'] as List)
            .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList(),
      );
}
