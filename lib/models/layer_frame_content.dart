import 'stroke.dart';

/// One layer's resolved content at a specific frame index - what to paint,
/// and at what opacity. Used by both the live editor (which includes
/// reference layers, since that's the point of a drawing guide) and export
/// (which only ever sees render-type layers).
class LayerFrameContent {
  final List<Stroke> strokes;
  final String? imagePath;
  final double opacity;

  const LayerFrameContent({required this.strokes, this.imagePath, this.opacity = 1.0});
}
