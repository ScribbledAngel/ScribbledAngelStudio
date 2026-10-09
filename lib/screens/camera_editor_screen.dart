import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/camera_state.dart';
import '../models/frame.dart';
import '../models/shot.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frame_painter.dart';

/// Sets up a simple camera move for a shot: where the "camera" starts and
/// where it ends. During playback (and later, export) the framing
/// interpolates smoothly between the two across the shot's frames. The
/// artwork itself never moves - this only changes how it's framed.
class CameraEditorScreen extends StatefulWidget {
  final String projectId;
  final String episodeId;
  final String shotId;

  const CameraEditorScreen({
    super.key,
    required this.projectId,
    required this.episodeId,
    required this.shotId,
  });

  @override
  State<CameraEditorScreen> createState() => _CameraEditorScreenState();
}

class _CameraEditorScreenState extends State<CameraEditorScreen> {
  bool _editingStart = true;
  late CameraState _localStart;
  late CameraState _localEnd;
  late bool _enabled;

  double _gestureStartZoom = 1.0;
  double _gestureStartRotation = 0;

  CameraState get _active => _editingStart ? _localStart : _localEnd;

  @override
  void initState() {
    super.initState();
    final shot = context.read<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId)!;
    _localStart = shot.cameraStart.copy();
    _localEnd = shot.cameraEnd.copy();
    _enabled = shot.cameraMoveEnabled;
  }

  Future<void> _persist() {
    return context.read<AppState>().updateShotCamera(
          widget.projectId,
          widget.episodeId,
          widget.shotId,
          enabled: _enabled,
          start: _localStart,
          end: _localEnd,
        );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartZoom = _active.zoom;
    _gestureStartRotation = _active.rotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size viewSize) {
    setState(() {
      _active.zoom = (_gestureStartZoom * details.scale).clamp(0.3, 6.0).toDouble();
      _active.rotation = _gestureStartRotation + details.rotation;
      _active.x += details.focalPointDelta.dx / viewSize.width;
      _active.y += details.focalPointDelta.dy / viewSize.height;
    });
  }

  void _resetActive() {
    setState(() {
      _active.x = 0;
      _active.y = 0;
      _active.zoom = 1.0;
      _active.rotation = 0;
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final shot = context.watch<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId);
    if (shot == null) {
      return const Scaffold(body: Center(child: Text('Shot not found')));
    }

    final AnimFrame? referenceFrame = shot.frames.isNotEmpty
        ? (_editingStart ? shot.frames.first : shot.frames.last)
        : (shot.storyboardFrame.strokes.isNotEmpty ? shot.storyboardFrame : null);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Camera move'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            SwitchListTile(
              value: _enabled,
              onChanged: (value) {
                setState(() => _enabled = value);
                _persist();
              },
              title: const Text('Enable camera move for this shot'),
              subtitle: const Text('When off, the camera stays still at the start framing.'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Start framing')),
                  ButtonSegment(value: false, label: Text('End framing')),
                ],
                selected: {_editingStart},
                onSelectionChanged: (selection) => setState(() => _editingStart = selection.first),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: shot.orientation.aspectRatio,
                  child: ClipRect(
                    child: Container(
                      color: Colors.white,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final viewSize = constraints.biggest;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: (details) => _onScaleUpdate(details, viewSize),
                            onScaleEnd: (_) => _persist(),
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..translate(_active.x * viewSize.width, _active.y * viewSize.height)
                                ..rotateZ(_active.rotation)
                                ..scale(_active.zoom),
                              child: referenceFrame == null
                                  ? const SizedBox.expand()
                                  : CustomPaint(
                                      size: viewSize,
                                      painter: FramePainter(strokes: referenceFrame.strokes),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pinch to zoom, drag to pan, twist with two fingers to rotate '
                      'the ${_editingStart ? "start" : "end"} framing.',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                  TextButton(onPressed: _resetActive, child: const Text('Reset')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
