import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/shot.dart';
import '../models/stroke.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/prompt_dialog.dart';
import '../widgets/timeline_strip.dart';

const _palette = <Color>[
  Colors.black,
  Color(0xFF6B6B6B),
  Colors.white,
  Color(0xFFE63946),
  Color(0xFFF4A261),
  Color(0xFFF7D154),
  Color(0xFF6BCB77),
  Color(0xFF2A9D8F),
  Color(0xFF3A86FF),
  Color(0xFF5E60CE),
  Color(0xFF9D4EDD),
  Color(0xFFFF7A9F),
  Color(0xFF8D5524),
];

class ShotEditorScreen extends StatefulWidget {
  final String projectId;
  final String episodeId;
  final String shotId;

  const ShotEditorScreen({
    super.key,
    required this.projectId,
    required this.episodeId,
    required this.shotId,
  });

  @override
  State<ShotEditorScreen> createState() => _ShotEditorScreenState();
}

class _ShotEditorScreenState extends State<ShotEditorScreen> {
  int _currentFrameIndex = 0;
  DrawTool _tool = DrawTool.pencil;
  Color _color = Colors.black;
  double _brushSize = 6;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];

  AppState get _appState => context.read<AppState>();

  Shot? get _shot => context.read<AppState>().getShot(
        widget.projectId,
        widget.episodeId,
        widget.shotId,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAtLeastOneFrame());
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _ensureAtLeastOneFrame() async {
    if (!mounted) return;
    final shot = _shot;
    if (shot != null && shot.frames.isEmpty) {
      await _appState.addFrame(widget.projectId, widget.episodeId, widget.shotId);
    }
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (_isPlaying) setState(() => _isPlaying = false);
  }

  void _togglePlayback(Shot shot) {
    if (_isPlaying) {
      _stopPlayback();
      return;
    }
    if (shot.frames.length < 2) return;
    setState(() => _isPlaying = true);
    final frameMs = (1000 / shot.fps).round();
    _playbackTimer = Timer.periodic(Duration(milliseconds: frameMs), (_) {
      final current = _shot;
      if (current == null || current.frames.isEmpty) return;
      setState(() {
        _currentFrameIndex = (_currentFrameIndex + 1) % current.frames.length;
      });
    });
  }

  void _selectFrame(int index) {
    if (_isPlaying) _stopPlayback();
    setState(() {
      _currentFrameIndex = index;
      _undoStack.clear();
      _redoStack.clear();
    });
  }

  void _handleStrokesChanged(List<Stroke> newStrokes) {
    final shot = _shot;
    if (shot == null || _currentFrameIndex >= shot.frames.length) return;
    final previous = shot.frames[_currentFrameIndex].strokes.map((s) => s.copy()).toList();
    _undoStack.add(previous);
    _redoStack.clear();
    _appState.updateFrameStrokes(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      _currentFrameIndex,
      newStrokes,
    );
  }

  void _undo() {
    final shot = _shot;
    if (shot == null || _undoStack.isEmpty) return;
    final current = shot.frames[_currentFrameIndex].strokes.map((s) => s.copy()).toList();
    _redoStack.add(current);
    final previous = _undoStack.removeLast();
    _appState.updateFrameStrokes(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      _currentFrameIndex,
      previous,
    );
    setState(() {});
  }

  void _redo() {
    final shot = _shot;
    if (shot == null || _redoStack.isEmpty) return;
    final current = shot.frames[_currentFrameIndex].strokes.map((s) => s.copy()).toList();
    _undoStack.add(current);
    final next = _redoStack.removeLast();
    _appState.updateFrameStrokes(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      _currentFrameIndex,
      next,
    );
    setState(() {});
  }

  Future<void> _clearFrame() async {
    final shot = _shot;
    if (shot == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear this frame?',
      message: 'Erases every stroke on frame ${_currentFrameIndex + 1}. You can undo right after.',
      confirmLabel: 'Clear',
    );
    if (!confirmed) return;
    _handleStrokesChanged([]);
  }

  Future<void> _addFrame() async {
    _stopPlayback();
    final newFrame = await _appState.addFrame(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      afterIndex: _currentFrameIndex,
    );
    if (newFrame == null || !mounted) return;
    setState(() {
      _currentFrameIndex += 1;
      _undoStack.clear();
      _redoStack.clear();
    });
  }

  Future<void> _duplicateFrame(int index) async {
    _stopPlayback();
    final newIndex = await _appState.duplicateFrame(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      index,
    );
    if (newIndex == null || !mounted) return;
    setState(() {
      _currentFrameIndex = newIndex;
      _undoStack.clear();
      _redoStack.clear();
    });
  }

  Future<void> _deleteFrame(int index) async {
    final shot = _shot;
    if (shot == null || shot.frames.length <= 1) return;
    _stopPlayback();
    await _appState.deleteFrame(widget.projectId, widget.episodeId, widget.shotId, index);
    if (!mounted) return;
    setState(() {
      if (_currentFrameIndex >= index && _currentFrameIndex > 0) {
        _currentFrameIndex -= 1;
      }
      _undoStack.clear();
      _redoStack.clear();
    });
  }

  Future<void> _renameShot(Shot shot) async {
    final result = await showPromptDialog(
      context,
      title: 'Rename shot',
      fields: [PromptField(label: 'Name', initialValue: shot.name)],
    );
    if (result == null || result[0].isEmpty) return;
    await _appState.updateShotMeta(widget.projectId, widget.episodeId, widget.shotId, name: result[0]);
  }

  Future<void> _editNotes(Shot shot) async {
    final result = await showPromptDialog(
      context,
      title: 'Shot notes',
      fields: [PromptField(label: 'Notes', initialValue: shot.notes, maxLines: 5)],
    );
    if (result == null) return;
    await _appState.updateShotMeta(widget.projectId, widget.episodeId, widget.shotId, notes: result[0]);
  }

  void _changeFps(Shot shot, int delta) {
    final newFps = (shot.fps + delta).clamp(1, 30).toInt();
    _appState.updateShotMeta(widget.projectId, widget.episodeId, widget.shotId, fps: newFps);
  }

  Future<void> _toggleOrientation(Shot shot) async {
    final hasDrawings = shot.frames.any((f) => f.strokes.isNotEmpty);
    final newOrientation = shot.orientation == CanvasOrientation.landscape
        ? CanvasOrientation.portrait
        : CanvasOrientation.landscape;
    if (hasDrawings) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Switch canvas shape?',
        message: 'This shot already has drawings. Changing from '
            '${shot.orientation == CanvasOrientation.landscape ? 'widescreen' : 'vertical'} to '
            '${newOrientation == CanvasOrientation.landscape ? 'widescreen' : 'vertical'} will '
            'stretch/distort existing frames to fit the new shape.',
        confirmLabel: 'Switch anyway',
        isDanger: false,
      );
      if (!confirmed) return;
    }
    await _appState.updateShotMeta(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      orientation: newOrientation,
    );
  }

  void _pickColor() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final swatch in _palette)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _color = swatch;
                      _tool = DrawTool.pencil;
                    });
                    Navigator.pop(sheetContext);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: swatch == _color ? AppColors.accent : Colors.white24,
                        width: swatch == _color ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickBrushSize() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Brush size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: _brushSize * 2,
                    height: _brushSize * 2,
                    decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
                  ),
                ),
                Slider(
                  min: 1,
                  max: 36,
                  value: _brushSize,
                  onChanged: (value) {
                    setSheetState(() {});
                    setState(() => _brushSize = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMoveComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Move & select tools are coming in a future update ✏️')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shot = context.watch<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId);

    if (shot == null) {
      return const Scaffold(body: Center(child: Text('Shot not found')));
    }

    final maxIndex = shot.frames.isEmpty ? 0 : shot.frames.length - 1;
    final frameIndex = _currentFrameIndex < 0
        ? 0
        : (_currentFrameIndex > maxIndex ? maxIndex : _currentFrameIndex);
    final hasFrames = shot.frames.isNotEmpty;
    final currentFrame = hasFrames ? shot.frames[frameIndex] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: GestureDetector(
          onTap: () => _renameShot(shot),
          child: Text(shot.name, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            tooltip: _isPlaying ? 'Pause' : 'Play',
            icon: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 32),
            onPressed: shot.frames.length < 2 ? null : () => _togglePlayback(shot),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'notes') _editNotes(shot);
              if (value == 'rename') _renameShot(shot);
              if (value == 'orientation') _toggleOrientation(shot);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename shot')),
              const PopupMenuItem(value: 'notes', child: Text('Edit notes')),
              PopupMenuItem(
                value: 'orientation',
                child: Text(
                  shot.orientation == CanvasOrientation.landscape
                      ? 'Switch to vertical (9:16)'
                      : 'Switch to widescreen (16:9)',
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: shot.orientation.aspectRatio,
                  child: currentFrame == null
                      ? const SizedBox.shrink()
                      : DrawingCanvas(
                          key: ValueKey(currentFrame.id),
                          strokes: currentFrame.strokes,
                          tool: _tool,
                          color: _color,
                          brushSize: _brushSize,
                          onStrokesChanged: _handleStrokesChanged,
                        ),
                ),
              ),
            ),
            _Toolbar(
              tool: _tool,
              color: _color,
              canUndo: _undoStack.isNotEmpty,
              canRedo: _redoStack.isNotEmpty,
              onSelectPencil: () => setState(() => _tool = DrawTool.pencil),
              onSelectEraser: () => setState(() => _tool = DrawTool.eraser),
              onPickColor: _pickColor,
              onPickBrushSize: _pickBrushSize,
              onUndo: _undo,
              onRedo: _redo,
              onClear: _clearFrame,
              onMove: _showMoveComingSoon,
            ),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text('FPS', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                    onPressed: () => _changeFps(shot, -1),
                  ),
                  Text('${shot.fps}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                    onPressed: () => _changeFps(shot, 1),
                  ),
                  const Spacer(),
                  Text(
                    '${shot.frames.length} frames · ${shot.durationSeconds.toStringAsFixed(1)}s',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            TimelineStrip(
              frames: shot.frames,
              currentIndex: frameIndex,
              onSelect: _selectFrame,
              onAddFrame: _addFrame,
              onDuplicate: _duplicateFrame,
              onDelete: _deleteFrame,
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final DrawTool tool;
  final Color color;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onSelectPencil;
  final VoidCallback onSelectEraser;
  final VoidCallback onPickColor;
  final VoidCallback onPickBrushSize;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onMove;

  const _Toolbar({
    required this.tool,
    required this.color,
    required this.canUndo,
    required this.canRedo,
    required this.onSelectPencil,
    required this.onSelectEraser,
    required this.onPickColor,
    required this.onPickBrushSize,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.edit_rounded,
              selected: tool == DrawTool.pencil,
              onTap: onSelectPencil,
            ),
            _ToolButton(
              icon: Icons.auto_fix_normal_rounded,
              selected: tool == DrawTool.eraser,
              onTap: onSelectEraser,
            ),
            _ToolButton(
              icon: Icons.circle,
              iconColor: color,
              onTap: onPickColor,
            ),
            _ToolButton(icon: Icons.line_weight_rounded, onTap: onPickBrushSize),
            _ToolButton(icon: Icons.undo_rounded, onTap: canUndo ? onUndo : null),
            _ToolButton(icon: Icons.redo_rounded, onTap: canRedo ? onRedo : null),
            _ToolButton(icon: Icons.delete_sweep_outlined, onTap: onClear),
            _ToolButton(icon: Icons.open_with_rounded, onTap: onMove, badge: 'soon'),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final bool selected;
  final VoidCallback? onTap;
  final String? badge;

  const _ToolButton({
    required this.icon,
    this.iconColor,
    this.selected = false,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: selected ? AppColors.accent.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  icon,
                  size: 26,
                  color: disabled
                      ? AppColors.textSecondary.withOpacity(0.3)
                      : (iconColor ?? (selected ? AppColors.accent : AppColors.textPrimary)),
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('soon', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black)),
              ),
            ),
        ],
      ),
    );
  }
}
