import 'package:flutter/material.dart';

import '../models/stroke.dart';

/// Paints a list of strokes onto a canvas. Shared by the live drawing
/// canvas, onion-skin layers (future), and frame thumbnails.
class FramePainter extends CustomPainter {
  final List<Stroke> strokes;
  final double opacity;

  FramePainter({required this.strokes, this.opacity = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..strokeWidth = stroke.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver
        ..color = stroke.isEraser
            ? Colors.black
            : (opacity >= 1.0 ? stroke.color : stroke.color.withOpacity(opacity));

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width / 2, paint..style = PaintingStyle.fill);
        continue;
      }

      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FramePainter oldDelegate) {
    // Strokes are mutated in place while actively drawing, so a reference
    // check alone would miss every in-progress update - just always repaint.
    // These are simple vector strokes, so the cost is trivial.
    return true;
  }
}
