import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/reference_asset_service.dart';
import '../models/layer_frame_content.dart';
import '../models/stroke.dart';
import 'frame_painter.dart';

enum DrawTool { pencil, eraser }

const _uuid = Uuid();

/// The live, touch-drawable canvas for one frame.
///
/// Give this widget a `ValueKey` based on the frame's id from the caller -
/// that's what makes it reset its drawing state cleanly whenever the
/// selected frame changes.
///
/// A single finger always draws. A second finger pinches/pans the view so
/// you can zoom in for detail work - strokes are still recorded in the
/// frame's real (un-zoomed) coordinates, so what you draw lines up no
/// matter how zoomed in you were.
class DrawingCanvas extends StatefulWidget {
  final List<Stroke> strokes;
  final DrawTool tool;
  final Color color;
  final double brushSize;
  final ValueChanged<List<Stroke>> onStrokesChanged;

  /// Onion-skin ghost layers - the previous/next frame's strokes, shown
  /// faintly behind the live drawing. Pass null/0 to disable.
  final List<Stroke>? onionBeforeStrokes;
  final List<Stroke>? onionAfterStrokes;
  final double onionOpacity;

  /// Other visible layers of this SAME frame, shown in full color but not
  /// interactive - bottom-to-top order, split by whether they sit below or
  /// above the layer being drawn on, so the active layer draws in its
  /// correct stacking position. Each is kept as its own paint layer (not
  /// merged into one list) so an eraser stroke on one layer can't bleed
  /// into another's content.
  final List<LayerFrameContent> layersBelow;
  final List<LayerFrameContent> layersAbove;

  /// Whether the layer being drawn on is itself visible. Drawing still
  /// works either way (so toggling visibility back on reveals what you
  /// drew), but when false its strokes aren't painted.
  final bool showActiveLayer;

  /// The active layer's own opacity and reference image (e.g. drawing
  /// directly on top of a reference frame).
  final double activeOpacity;
  final String? activeImagePath;

  /// False when the active layer is a Reference layer - reference content
  /// is a guide, never exported, so drawing onto it would silently discard
  /// the artwork from the final video. Pinch-to-zoom/pan still works; only
  /// starting a new stroke is blocked.
  final bool drawingEnabled;

  const DrawingCanvas({
    super.key,
    required this.strokes,
    required this.tool,
    required this.color,
    required this.brushSize,
    required this.onStrokesChanged,
    this.onionBeforeStrokes,
    this.onionAfterStrokes,
    this.onionOpacity = 0,
    this.layersBelow = const [],
    this.layersAbove = const [],
    this.showActiveLayer = true,
    this.activeOpacity = 1.0,
    this.activeImagePath,
    this.drawingEnabled = true,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  static const double _minScale = 1.0;
  static const double _maxScale = 6.0;

  late List<Stroke> _strokes;
  Stroke? _activeStroke;
  bool _isDrawingGesture = false;

  double _viewScale = 1.0;
  double _gestureStartScale = 1.0;
  Offset _viewTranslation = Offset.zero;
  // The artwork-space point currently anchored under the fingers while
  // zooming/panning, so the pinch feels centered on your fingers instead of
  // always scaling away from the top-left corner.
  Offset? _zoomAnchorArtworkPoint;

  // Raw finger-down/up tracking, independent of the scale gesture recognizer.
  // A pinch that barely moves never fires a "scale update" event at all, so
  // relying only on that would still let a stray dot through - this fires
  // immediately for every touch regardless of movement.
  int _rawPointerCount = 0;
  bool _secondFingerTouchedDuringStroke = false;

  @override
  void initState() {
    super.initState();
    _strokes = widget.strokes.map((s) => s.copy()).toList();
  }

  @override
  void didUpdateWidget(covariant DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resync from the canonical (parent-held) strokes whenever they change
    // externally - e.g. undo/redo - but never mid-gesture, so we don't wipe
    // out a stroke the user is actively drawing.
    if (_activeStroke == null) {
      _strokes = widget.strokes.map((s) => s.copy()).toList();
    }
  }

  Offset _toArtworkSpace(Offset screenPoint) {
    return (screenPoint - _viewTranslation) / _viewScale;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _rawPointerCount++;
    if (_activeStroke != null && _rawPointerCount > 1) {
      // A second finger just touched down mid-stroke - cancel it right now,
      // before the gesture recognizer even catches up. Waiting for that
      // would risk one visible frame of a stray mark before removal.
      _secondFingerTouchedDuringStroke = true;
      _isDrawingGesture = false;
      _abortStroke();
    }
  }

  void _handlePointerUp(PointerEvent event) {
    if (_rawPointerCount > 0) _rawPointerCount--;
  }

  void _startStroke(Offset point) {
    // Don't add it to the visible strokes yet - only once it has more than
    // one point. A pinch-to-zoom start often registers as a single finger
    // touching down a few milliseconds before the second, and we don't want
    // that split-second contact to flash a stray dot.
    _secondFingerTouchedDuringStroke = false;
    _activeStroke = Stroke(
      id: _uuid.v4(),
      colorValue: widget.color.value,
      width: widget.brushSize,
      isEraser: widget.tool == DrawTool.eraser,
    )..points.add(point);
  }

  void _extendStroke(Offset point) {
    final stroke = _activeStroke;
    if (stroke == null) return;
    setState(() {
      stroke.points.add(point);
      if (!_strokes.contains(stroke)) {
        _strokes.add(stroke);
      }
    });
  }

  void _commitStroke() {
    final stroke = _activeStroke;
    if (stroke == null) return;
    _activeStroke = null;
    if (!_strokes.contains(stroke)) {
      if (_secondFingerTouchedDuringStroke) {
        // A second finger touched down during what looked like a tap -
        // this was an attempted pinch that never moved enough to be
        // detected as a scale gesture. Discard it rather than drawing a dot.
        return;
      }
      // Only ever got a single point - a deliberate tap-dot. Show it now.
      setState(() => _strokes.add(stroke));
    }
    widget.onStrokesChanged(_strokes.map((s) => s.copy()).toList());
  }

  void _abortStroke() {
    final stroke = _activeStroke;
    if (stroke == null) return;
    _activeStroke = null;
    if (_strokes.contains(stroke)) {
      setState(() => _strokes.remove(stroke));
    }
  }

  void _resetView() {
    setState(() {
      _viewScale = 1.0;
      _viewTranslation = Offset.zero;
    });
  }

  void _beginZoom(Offset screenFocalPoint) {
    _isDrawingGesture = false;
    _zoomAnchorArtworkPoint = _toArtworkSpace(screenFocalPoint);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _viewScale;
    if (details.pointerCount <= 1 && widget.drawingEnabled) {
      _isDrawingGesture = true;
      _startStroke(_toArtworkSpace(details.localFocalPoint));
    } else {
      _beginZoom(details.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isDrawingGesture && details.pointerCount > 1) {
      // A second finger joined mid-stroke - abandon the draw and zoom instead.
      _abortStroke();
      _beginZoom(details.localFocalPoint);
    }

    if (_isDrawingGesture) {
      _extendStroke(_toArtworkSpace(details.localFocalPoint));
      return;
    }

    final newScale = (_gestureStartScale * details.scale).clamp(_minScale, _maxScale);
    final anchor = _zoomAnchorArtworkPoint ?? _toArtworkSpace(details.localFocalPoint);
    setState(() {
      _viewScale = newScale;
      // Keep the artwork point under the fingers fixed on screen, so the
      // zoom grows from wherever you're pinching, not the canvas corner.
      _viewTranslation = details.localFocalPoint - anchor * newScale;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isDrawingGesture) _commitStroke();
    _isDrawingGesture = false;
    _zoomAnchorArtworkPoint = null;
  }

  Widget _buildLayerContent(
    List<Stroke> strokes,
    double opacity,
    String? imagePath, {
    bool foreground = false,
  }) {
    if (imagePath == null && strokes.isEmpty && !foreground) return const SizedBox.shrink();
    final painter = FramePainter(strokes: strokes, opacity: opacity);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imagePath != null)
          Opacity(
            opacity: opacity,
            child: Image.file(
              File(ReferenceAssetService().fullPathFor(imagePath)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
        foreground ? CustomPaint(foregroundPainter: painter) : CustomPaint(painter: painter),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isZoomed = _viewScale > 1.01;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerUp,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(_viewTranslation.dx, _viewTranslation.dy)
                    ..scale(_viewScale),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.white),
                      if (widget.onionOpacity > 0 && (widget.onionBeforeStrokes?.isNotEmpty ?? false))
                        CustomPaint(
                          painter: FramePainter(
                            strokes: widget.onionBeforeStrokes!,
                            opacity: widget.onionOpacity,
                            tintColor: Colors.blue,
                          ),
                        ),
                      if (widget.onionOpacity > 0 && (widget.onionAfterStrokes?.isNotEmpty ?? false))
                        CustomPaint(
                          painter: FramePainter(
                            strokes: widget.onionAfterStrokes!,
                            opacity: widget.onionOpacity,
                            tintColor: Colors.red,
                          ),
                        ),
                      for (final content in widget.layersBelow)
                        _buildLayerContent(content.strokes, content.opacity, content.imagePath),
                      if (widget.showActiveLayer)
                        _buildLayerContent(_strokes, widget.activeOpacity, widget.activeImagePath, foreground: true),
                      for (final content in widget.layersAbove)
                        _buildLayerContent(content.strokes, content.opacity, content.imagePath),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isZoomed)
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 20),
                  tooltip: 'Reset zoom',
                  onPressed: _resetView,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
