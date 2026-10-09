import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/shot.dart';
import '../models/stroke.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/prompt_dialog.dart';

/// A small, single-frame sketch editor for a shot's storyboard thumbnail -
/// deliberately simpler than the full Animation Editor since there's no
/// timeline here, just one drawing.
class StoryboardSketchScreen extends StatefulWidget {
  final String projectId;
  final String episodeId;
  final String shotId;

  const StoryboardSketchScreen({
    super.key,
    required this.projectId,
    required this.episodeId,
    required this.shotId,
  });

  @override
  State<StoryboardSketchScreen> createState() => _StoryboardSketchScreenState();
}

class _StoryboardSketchScreenState extends State<StoryboardSketchScreen> {
  DrawTool _tool = DrawTool.pencil;
  Color _color = Colors.black;
  double _brushSize = 6;

  void _handleStrokesChanged(List<Stroke> strokes) {
    context
        .read<AppState>()
        .updateStoryboardStrokes(widget.projectId, widget.episodeId, widget.shotId, strokes);
  }

  Future<void> _clear() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear storyboard sketch?',
      message: 'This only clears the storyboard thumbnail, not your animated frames.',
      confirmLabel: 'Clear',
    );
    if (confirmed) _handleStrokesChanged([]);
  }

  @override
  Widget build(BuildContext context) {
    final shot = context.watch<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId);
    if (shot == null) {
      return const Scaffold(body: Center(child: Text('Shot not found')));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Storyboard · ${shot.name}'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep_outlined), onPressed: _clear),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: shot.orientation.aspectRatio,
                  child: DrawingCanvas(
                    key: ValueKey(shot.storyboardFrame.id),
                    strokes: shot.storyboardFrame.strokes,
                    tool: _tool,
                    color: _color,
                    brushSize: _brushSize,
                    onStrokesChanged: _handleStrokesChanged,
                  ),
                ),
              ),
            ),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded),
                    color: _tool == DrawTool.pencil ? AppColors.accent : AppColors.textPrimary,
                    onPressed: () => setState(() => _tool = DrawTool.pencil),
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_fix_normal_rounded),
                    color: _tool == DrawTool.eraser ? AppColors.accent : AppColors.textPrimary,
                    onPressed: () => setState(() => _tool = DrawTool.eraser),
                  ),
                  GestureDetector(
                    onTap: () => _showColorPicker(context),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.circle, color: _color, size: 26),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    const swatches = <Color>[
      Colors.black,
      Color(0xFF6B6B6B),
      Color(0xFFE63946),
      Color(0xFF3A86FF),
      Color(0xFF6BCB77),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 14,
            children: [
              for (final swatch in swatches)
                GestureDetector(
                  onTap: () {
                    setState(() => _color = swatch);
                    Navigator.pop(sheetContext);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
