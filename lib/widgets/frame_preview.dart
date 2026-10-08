import 'package:flutter/material.dart';

import '../models/frame.dart';
import 'frame_painter.dart';

/// A small read-only render of a frame's strokes, used for timeline and
/// shot-list thumbnails.
class FramePreview extends StatelessWidget {
  final AnimFrame? frame;
  final double width;
  final double height;
  final Color background;

  const FramePreview({
    super.key,
    required this.frame,
    this.width = 64,
    this.height = 96,
    this.background = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: background,
      child: frame == null
          ? const SizedBox.shrink()
          : CustomPaint(
              size: Size(width, height),
              painter: FramePainter(strokes: frame!.strokes),
            ),
    );
  }
}
