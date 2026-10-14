import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../data/audio_service.dart';
import '../data/reference_asset_service.dart';
import '../models/audio_clip.dart';
import '../models/camera_state.dart';
import '../models/layer.dart';
import '../models/layer_frame_content.dart';
import '../models/shot.dart';
import '../models/stroke.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/frame_painter.dart';
import '../widgets/prompt_dialog.dart';
import '../widgets/timeline_strip.dart';
import 'camera_editor_screen.dart';
import 'export_screen.dart';
import 'video_import_screen.dart';

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
  String? _activeLayerId;
  bool _recordingCanvasSize = false;
  bool _isPreloadingPlayback = false;
  DrawTool _tool = DrawTool.pencil;
  Color _color = Colors.black;
  double _brushSize = 6;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  bool _onionSkinEnabled = false;
  double _onionOpacity = 0.3;

  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];

  final AudioService _audioService = AudioService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;

  List<double>? _audioWaveformPeaks;
  String? _waveformKey;

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
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _ensureAtLeastOneFrame() async {
    if (!mounted) return;
    final shot = _shot;
    if (shot != null && shot.frameCount == 0 && shot.layers.isNotEmpty) {
      await _appState.addFrame(
        widget.projectId,
        widget.episodeId,
        widget.shotId,
        activeLayerId: shot.layers.first.id,
      );
    }
  }

  /// Picks a valid active layer if none is set yet, or the previously
  /// active one was deleted - defaults to the top (frontmost) layer.
  void _ensureActiveLayer(Shot shot) {
    if (shot.layers.isEmpty) return;
    final stillExists = shot.layers.any((l) => l.id == _activeLayerId);
    if (!stillExists) _activeLayerId = shot.layers.last.id;
  }

  Layer? _activeLayer(Shot shot) {
    for (final l in shot.layers) {
      if (l.id == _activeLayerId) return l;
    }
    return null;
  }

  /// Recomputes the under-timeline waveform (one peak per frame) whenever
  /// the audio clip, its trim, or the frame grid actually changes - cheap
  /// to call every build since it no-ops unless the key changed.
  void _maybeRefreshWaveform(Shot shot) {
    final clip = shot.audioClip;
    final key = clip == null
        ? null
        : '${clip.fileName}|${clip.trimStart}|${shot.frameCount}|${shot.fps}';
    if (key == _waveformKey) return;
    _waveformKey = key;

    if (clip == null || shot.frameCount == 0 || shot.fps <= 0) {
      if (_audioWaveformPeaks != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _audioWaveformPeaks = null);
        });
      }
      return;
    }

    final endSeconds =
        (clip.trimStart + shot.frameCount / shot.fps).clamp(0.0, clip.sourceDurationSeconds);
    _audioService
        .extractWaveformPeaks(
      fileName: clip.fileName,
      startSeconds: clip.trimStart,
      endSeconds: endSeconds,
      sampleCount: shot.frameCount,
    )
        .then((peaks) {
      if (!mounted || key != _waveformKey) return; // superseded by a newer change
      setState(() => _audioWaveformPeaks = peaks);
    });
  }

  DateTime? _playbackStartTime;

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackStartTime = null;
    _audioPlayer.stop();
    if (_isPlaying) setState(() => _isPlaying = false);
  }

  Future<void> _playAudioFromStart(AudioClip clip) async {
    try {
      await _audioPlayer.setFilePath(await _audioService.fullPathFor(clip.fileName));
      await _audioPlayer.setVolume(clip.volume);
      await _audioPlayer.seek(Duration(milliseconds: (clip.trimStart * 1000).round()));
      await _audioPlayer.play();
    } catch (_) {
      // Missing/corrupt audio file shouldn't block frame playback.
    }
  }

  /// Decodes every reference image used anywhere in the shot into Flutter's
  /// image cache before playback starts. Without this, each frame change
  /// during playback asks `Image.file` to decode a brand-new file from disk
  /// on the spot, which doesn't complete instantly - the gap shows as a
  /// flash of whatever's behind it (black, here) between frames.
  Future<void> _precacheReferenceImages(Shot shot) async {
    final paths = <String>{};
    for (final layer in shot.layers) {
      for (final frame in layer.frames) {
        final path = frame.imagePath;
        if (path != null) paths.add(path);
      }
    }
    if (paths.isEmpty || !mounted) return;
    final referenceAssets = ReferenceAssetService();
    await Future.wait(
      paths.map(
        (p) => precacheImage(FileImage(File(referenceAssets.fullPathFor(p))), context).catchError((_) {}),
      ),
    );
  }

  Future<void> _togglePlayback(Shot shot) async {
    if (_isPlaying) {
      _stopPlayback();
      return;
    }
    if (shot.frameCount < 2 || _isPreloadingPlayback) return;
    setState(() => _isPreloadingPlayback = true);
    await _precacheReferenceImages(shot);
    if (!mounted) return;
    setState(() {
      _isPreloadingPlayback = false;
      _isPlaying = true;
    });
    final clip = shot.audioClip;
    if (clip != null) _playAudioFromStart(clip);
    final frameMs = 1000 / shot.fps;
    _playbackStartTime = DateTime.now();
    // Poll frequently and derive the frame from real elapsed time, rather
    // than just advancing by one tick each time - a plain periodic counter
    // drifts out of sync with audio (which tracks a real clock) over a few
    // seconds, since each Timer tick is scheduled independently.
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final current = _shot;
      final startTime = _playbackStartTime;
      if (current == null || current.frameCount == 0 || startTime == null) return;
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      final totalFrames = current.frameCount;
      final loopedIndex = (elapsedMs / frameMs).floor() % totalFrames;
      if (loopedIndex == _currentFrameIndex) return;
      if (loopedIndex < _currentFrameIndex && current.audioClip != null) {
        _playAudioFromStart(current.audioClip!);
      }
      setState(() => _currentFrameIndex = loopedIndex);
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
    final layer = shot == null ? null : _activeLayer(shot);
    if (layer == null || _currentFrameIndex >= layer.frames.length) return;
    final previous = layer.frames[_currentFrameIndex].strokes.map((s) => s.copy()).toList();
    _undoStack.add(previous);
    _redoStack.clear();
    _appState.updateFrameStrokes(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      layer.id,
      _currentFrameIndex,
      newStrokes,
    );
  }

  void _undo() {
    final shot = _shot;
    final layer = shot == null ? null : _activeLayer(shot);
    if (layer == null || _undoStack.isEmpty) return;
    final current = layer.frames[_currentFrameIndex].strokes.map((s) => s.copy()).toList();
    _redoStack.add(current);
    final previous = _undoStack.removeLast();
    _appState.updateFrameStrokes(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      layer.id,
      _currentFrameIndex,
      previous,
    );
    setState(() {});
  }

  void _redo() {
    final shot = _shot;
    final layer = shot == null ? null : _activeLayer(shot);
    if (layer == null || _redoStack.isEmpty) return;
    final current = layer.frames[_currentFrameIndex].strokes.map((s) => s.copy()).toList();
    _undoStack.add(current);
    final next = _redoStack.removeLast();
    _appState.updateFrameStrokes(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      layer.id,
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
    final shot = _shot;
    final layer = shot == null ? null : _activeLayer(shot);
    if (layer == null) return;
    _stopPlayback();
    final newFrame = await _appState.addFrame(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      activeLayerId: layer.id,
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
    if (shot == null || shot.frameCount <= 1) return;
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
    final hasDrawings = shot.hasAnyStrokes;
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

  Future<void> _startRecording() async {
    final granted = await _audioService.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is needed to record audio.')),
        );
      }
      return;
    }
    final started = await _audioService.startRecording();
    if (started && mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final clip = await _audioService.stopRecording();
    if (mounted) setState(() => _isRecording = false);
    if (clip != null) {
      await _appState.setShotAudio(widget.projectId, widget.episodeId, widget.shotId, clip);
    }
  }

  Future<void> _importAudio() async {
    final clip = await _audioService.importAudioFile();
    if (clip != null) {
      await _appState.setShotAudio(widget.projectId, widget.episodeId, widget.shotId, clip);
    }
  }

  Future<void> _deleteAudio(AudioClip clip) async {
    await _audioPlayer.stop();
    await _audioService.deleteFile(clip.fileName);
    await _appState.clearShotAudio(widget.projectId, widget.episodeId, widget.shotId);
  }

  void _openAudioPanel() {
    _stopPlayback();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final shot = context.watch<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId);
          if (shot == null) return const SizedBox.shrink();
          final clip = shot.audioClip;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Shot audio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  if (clip == null)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(_isRecording ? Icons.stop_circle_rounded : Icons.mic_rounded),
                            label: Text(_isRecording ? 'Stop recording' : 'Record'),
                            onPressed: () async {
                              if (_isRecording) {
                                await _stopRecording();
                              } else {
                                await _startRecording();
                              }
                              setSheetState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.file_upload_outlined),
                            label: const Text('Import'),
                            onPressed: _isRecording
                                ? null
                                : () async {
                                    await _importAudio();
                                    setSheetState(() {});
                                  },
                          ),
                        ),
                      ],
                    )
                  else ...[
                    Text(
                      '${clip.sourceDurationSeconds.toStringAsFixed(1)}s source · '
                      '${clip.effectiveDuration.toStringAsFixed(1)}s used',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    const Text('Trim', style: TextStyle(fontSize: 12)),
                    RangeSlider(
                      min: 0,
                      max: clip.sourceDurationSeconds > 0 ? clip.sourceDurationSeconds : 1,
                      values: RangeValues(
                        clip.trimStart.clamp(0, clip.sourceDurationSeconds).toDouble(),
                        clip.trimEnd.clamp(0, clip.sourceDurationSeconds).toDouble(),
                      ),
                      onChanged: (values) {
                        clip.trimStart = values.start;
                        clip.trimEnd = values.end;
                        setSheetState(() {});
                        _appState.updateShotAudio(
                          widget.projectId,
                          widget.episodeId,
                          widget.shotId,
                          trimStart: values.start,
                          trimEnd: values.end,
                        );
                      },
                    ),
                    const Text('Volume', style: TextStyle(fontSize: 12)),
                    Slider(
                      min: 0,
                      max: 1,
                      value: clip.volume,
                      onChanged: (value) {
                        clip.volume = value;
                        setSheetState(() {});
                        _appState.updateShotAudio(
                          widget.projectId,
                          widget.episodeId,
                          widget.shotId,
                          volume: value,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Preview'),
                            onPressed: () => _playAudioFromStart(clip),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                            label: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                            onPressed: () async {
                              await _deleteAudio(clip);
                              setSheetState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openCameraEditor() {
    _stopPlayback();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraEditorScreen(
          projectId: widget.projectId,
          episodeId: widget.episodeId,
          shotId: widget.shotId,
        ),
      ),
    );
  }

  void _openExport() {
    _stopPlayback();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          projectId: widget.projectId,
          episodeId: widget.episodeId,
          shotId: widget.shotId,
        ),
      ),
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

  void _toggleOnionSkin() {
    setState(() => _onionSkinEnabled = !_onionSkinEnabled);
  }

  void _pickOnionOpacity() {
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
                const Text('Onion skin strength', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'Blue = previous frame · Red = next frame',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                Slider(
                  min: 0.1,
                  max: 0.7,
                  value: _onionOpacity,
                  onChanged: (value) {
                    setSheetState(() {});
                    setState(() => _onionOpacity = value);
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

  void _selectLayer(String layerId) {
    setState(() {
      _activeLayerId = layerId;
      _undoStack.clear();
      _redoStack.clear();
    });
  }

  Future<void> _addLayer() async {
    final layer = await _appState.addLayer(widget.projectId, widget.episodeId, widget.shotId);
    if (layer == null || !mounted) return;
    _selectLayer(layer.id);
  }

  Future<LayerType?> _askLayerType({required String title}) {
    return showDialog<LayerType>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Reference: visible while you draw, as a guide, but never appears in the exported video.\n\n'
          'Render: included in the final export, like any drawn layer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(LayerType.reference),
            child: const Text('Reference'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(LayerType.render),
            child: const Text('Render'),
          ),
        ],
      ),
    );
  }

  Future<void> _addImageLayer() async {
    final imagePath = await ReferenceAssetService().importImage();
    if (imagePath == null || !mounted) return;
    final type = await _askLayerType(title: 'Use this image as…');
    if (type == null || !mounted) return;
    final layer = await _appState.addLayer(
      widget.projectId,
      widget.episodeId,
      widget.shotId,
      name: type == LayerType.reference ? 'Image Reference' : 'Image',
      type: type,
      imagePath: imagePath,
    );
    if (layer == null || !mounted) return;
    _selectLayer(layer.id);
  }

  Future<void> _renameLayer(Layer layer) async {
    final result = await showPromptDialog(
      context,
      title: 'Rename layer',
      fields: [PromptField(label: 'Name', initialValue: layer.name)],
    );
    if (result == null || result[0].isEmpty) return;
    await _appState.renameLayer(widget.projectId, widget.episodeId, widget.shotId, layer.id, result[0]);
  }

  Future<void> _deleteLayer(Layer layer) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${layer.name}"?',
      message: 'This deletes everything drawn on this layer, in every frame. This cannot be undone.',
    );
    if (!confirmed) return;
    await _appState.deleteLayer(widget.projectId, widget.episodeId, widget.shotId, layer.id);
  }

  void _openLayerPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final shot = context.watch<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId);
          if (shot == null) return const SizedBox.shrink();
          // Shown top-to-bottom matching the visual stack: frontmost first.
          final layersTopFirst = shot.layers.reversed.toList();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        const Text('Layers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.videocam_outlined, size: 18),
                          label: const Text('Video'),
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VideoImportScreen(
                                  projectId: widget.projectId,
                                  episodeId: widget.episodeId,
                                  shotId: widget.shotId,
                                ),
                              ),
                            );
                            if (mounted) _openLayerPanel();
                          },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('Image'),
                          onPressed: () async {
                            await _addImageLayer();
                            setSheetState(() {});
                          },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                          onPressed: () async {
                            await _addLayer();
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.5),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: layersTopFirst.length,
                      itemBuilder: (context, displayIndex) {
                        final layer = layersTopFirst[displayIndex];
                        final isActive = layer.id == _activeLayerId;
                        final realIndex = shot.layers.length - 1 - displayIndex;
                        final isReference = layer.type == LayerType.reference;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: isActive ? AppColors.accent.withOpacity(0.15) : AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                _selectLayer(layer.id);
                                setSheetState(() {});
                              },
                              onLongPress: () async {
                                await _renameLayer(layer);
                                setSheetState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            layer.visible ? Icons.visibility_rounded : Icons.visibility_off_outlined,
                                            color: layer.visible ? AppColors.textPrimary : AppColors.textSecondary,
                                          ),
                                          onPressed: () async {
                                            await _appState.toggleLayerVisibility(
                                              widget.projectId,
                                              widget.episodeId,
                                              widget.shotId,
                                              layer.id,
                                            );
                                            setSheetState(() {});
                                          },
                                        ),
                                        Expanded(
                                          child: Text(
                                            layer.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                              color: isActive ? AppColors.accent : AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () async {
                                            await _appState.setLayerType(
                                              widget.projectId,
                                              widget.episodeId,
                                              widget.shotId,
                                              layer.id,
                                              isReference ? LayerType.render : LayerType.reference,
                                            );
                                            setSheetState(() {});
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: (isReference ? AppColors.warning : AppColors.success)
                                                  .withOpacity(0.18),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isReference ? Icons.visibility_outlined : Icons.movie_filter_outlined,
                                                  size: 13,
                                                  color: isReference ? AppColors.warning : AppColors.success,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isReference ? 'Reference' : 'Render',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isReference ? AppColors.warning : AppColors.success,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                                          onSelected: (value) async {
                                            if (value == 'up') {
                                              await _appState.reorderLayers(
                                                widget.projectId,
                                                widget.episodeId,
                                                widget.shotId,
                                                realIndex,
                                                realIndex + 2,
                                              );
                                            } else if (value == 'down') {
                                              await _appState.reorderLayers(
                                                widget.projectId,
                                                widget.episodeId,
                                                widget.shotId,
                                                realIndex,
                                                realIndex - 1,
                                              );
                                            } else if (value == 'rename') {
                                              await _renameLayer(layer);
                                            } else if (value == 'delete') {
                                              await _deleteLayer(layer);
                                            }
                                            setSheetState(() {});
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'up',
                                              enabled: realIndex < shot.layers.length - 1,
                                              child: const Text('Move up'),
                                            ),
                                            PopupMenuItem(
                                              value: 'down',
                                              enabled: realIndex > 0,
                                              child: const Text('Move down'),
                                            ),
                                            const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                            PopupMenuItem(
                                              value: 'delete',
                                              enabled: shot.layers.length > 1,
                                              child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (layer.videoSource != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 44, bottom: 4),
                                        child: Text(
                                          'Video · ${layer.videoSource!.snippetStart.toStringAsFixed(1)}–'
                                          '${layer.videoSource!.snippetEnd.toStringAsFixed(1)}s · '
                                          '${layer.videoSource!.extractionFps.toStringAsFixed(0)} fps'
                                          '${layer.videoSource!.audioFileName != null ? ' · with audio' : ''}',
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        const SizedBox(width: 12),
                                        const Icon(Icons.opacity_rounded, size: 14, color: AppColors.textSecondary),
                                        Expanded(
                                          child: Slider(
                                            min: 0.1,
                                            max: 1.0,
                                            value: layer.opacity,
                                            onChanged: (value) {
                                              setSheetState(() {});
                                              _appState.setLayerOpacity(
                                                widget.projectId,
                                                widget.episodeId,
                                                widget.shotId,
                                                layer.id,
                                                value,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shot = context.watch<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId);

    if (shot == null) {
      return const Scaffold(body: Center(child: Text('Shot not found')));
    }

    _ensureActiveLayer(shot);
    final activeLayer = _activeLayer(shot);
    _maybeRefreshWaveform(shot);

    final maxIndex = shot.frameCount == 0 ? 0 : shot.frameCount - 1;
    final frameIndex = _currentFrameIndex < 0
        ? 0
        : (_currentFrameIndex > maxIndex ? maxIndex : _currentFrameIndex);
    final hasFrames = shot.frameCount > 0 && activeLayer != null;
    final activeFrame = hasFrames ? activeLayer.frames[frameIndex] : null;

    final layersBelow = <LayerFrameContent>[];
    final layersAbove = <LayerFrameContent>[];
    var passedActive = false;
    for (final layer in shot.layers) {
      if (layer.id == activeLayer?.id) {
        passedActive = true;
        continue;
      }
      if (!layer.visible || frameIndex >= layer.frames.length) continue;
      final frame = layer.frames[frameIndex];
      final content = LayerFrameContent(strokes: frame.strokes, imagePath: frame.imagePath, opacity: layer.opacity);
      (passedActive ? layersAbove : layersBelow).add(content);
    }

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
            icon: _isPreloadingPlayback
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 32),
            onPressed: shot.frameCount < 2 || _isPreloadingPlayback ? null : () => _togglePlayback(shot),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'notes') _editNotes(shot);
              if (value == 'rename') _renameShot(shot);
              if (value == 'orientation') _toggleOrientation(shot);
              if (value == 'camera') _openCameraEditor();
              if (value == 'audio') _openAudioPanel();
              if (value == 'export') _openExport();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename shot')),
              const PopupMenuItem(value: 'notes', child: Text('Edit notes')),
              const PopupMenuItem(value: 'camera', child: Text('Camera move')),
              const PopupMenuItem(value: 'audio', child: Text('Shot audio')),
              const PopupMenuItem(value: 'export', child: Text('Export video')),
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
            if (activeLayer != null && activeLayer.type == LayerType.reference)
              Container(
                width: double.infinity,
                color: AppColors.warning.withOpacity(0.15),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  '"${activeLayer.name}" is a Reference layer - a guide only, never exported. '
                  'Select a Render layer to draw.',
                  style: const TextStyle(fontSize: 11, color: AppColors.warning),
                ),
              ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: shot.orientation.aspectRatio,
                  child: activeFrame == null
                      ? const SizedBox.shrink()
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (shot.canvasWidthPx == null && !_recordingCanvasSize) {
                              _recordingCanvasSize = true;
                              final size = constraints.biggest;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _recordingCanvasSize = false;
                                if (!mounted) return;
                                _appState.recordCanvasSizeIfUnset(
                                  widget.projectId,
                                  widget.episodeId,
                                  widget.shotId,
                                  size.width,
                                  size.height,
                                );
                              });
                            }
                            return _isPlaying
                                ? _PlaybackPreview(
                                    contents: shot.editorLayerContentsAt(frameIndex),
                                    camera: shot.cameraMoveEnabled
                                        ? CameraState.lerp(
                                            shot.cameraStart,
                                            shot.cameraEnd,
                                            shot.frameCount > 1 ? frameIndex / (shot.frameCount - 1) : 0.0,
                                          )
                                        : null,
                                  )
                                : DrawingCanvas(
                                    key: ValueKey(activeFrame.id),
                                    strokes: activeFrame.strokes,
                                    tool: _tool,
                                    color: _color,
                                    brushSize: _brushSize,
                                    onStrokesChanged: _handleStrokesChanged,
                                    onionOpacity: _onionSkinEnabled ? _onionOpacity : 0,
                                    onionBeforeStrokes:
                                        frameIndex > 0 ? shot.compositeStrokesAt(frameIndex - 1) : null,
                                    onionAfterStrokes: frameIndex < shot.frameCount - 1
                                        ? shot.compositeStrokesAt(frameIndex + 1)
                                        : null,
                                    layersBelow: layersBelow,
                                    layersAbove: layersAbove,
                                    showActiveLayer: activeLayer!.visible,
                                    activeOpacity: activeLayer.opacity,
                                    activeImagePath: activeFrame.imagePath,
                                    drawingEnabled: activeLayer.type == LayerType.render,
                                  );
                          },
                        ),
                ),
              ),
            ),
            _Toolbar(
              tool: _tool,
              color: _color,
              canUndo: _undoStack.isNotEmpty,
              canRedo: _redoStack.isNotEmpty,
              onionSkinEnabled: _onionSkinEnabled,
              onSelectPencil: () => setState(() => _tool = DrawTool.pencil),
              onSelectEraser: () => setState(() => _tool = DrawTool.eraser),
              onPickColor: _pickColor,
              onPickBrushSize: _pickBrushSize,
              onUndo: _undo,
              onRedo: _redo,
              onClear: _clearFrame,
              onMove: _showMoveComingSoon,
              onToggleOnionSkin: _toggleOnionSkin,
              onPickOnionOpacity: _pickOnionOpacity,
              onOpenLayers: _openLayerPanel,
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
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _openLayerPanel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers_rounded, size: 14, color: AppColors.accent),
                          const SizedBox(width: 4),
                          Text(
                            activeLayer?.name ?? '',
                            style: const TextStyle(fontSize: 12, color: AppColors.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${shot.frameCount} frames · ${shot.durationSeconds.toStringAsFixed(1)}s',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            TimelineStrip(
              frameCount: shot.frameCount,
              compositeStrokesAt: shot.compositeStrokesAt,
              currentIndex: frameIndex,
              onSelect: _selectFrame,
              onAddFrame: _addFrame,
              onDuplicate: _duplicateFrame,
              onDelete: _deleteFrame,
              waveformPeaks: _audioWaveformPeaks,
              keyframeFrames: shot.audioKeyframeFrames,
              onToggleKeyframe: (index) => _appState.toggleAudioKeyframeAtFrame(
                widget.projectId,
                widget.episodeId,
                widget.shotId,
                index,
              ),
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
  final bool onionSkinEnabled;
  final VoidCallback onToggleOnionSkin;
  final VoidCallback onPickOnionOpacity;
  final VoidCallback onOpenLayers;

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
    required this.onOpenLayers,
    required this.onMove,
    required this.onionSkinEnabled,
    required this.onToggleOnionSkin,
    required this.onPickOnionOpacity,
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
            _ToolButton(
              icon: Icons.blur_on_rounded,
              selected: onionSkinEnabled,
              onTap: onToggleOnionSkin,
              onLongPress: onPickOnionOpacity,
            ),
            _ToolButton(icon: Icons.layers_rounded, onTap: onOpenLayers),
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
  final VoidCallback? onLongPress;
  final String? badge;

  const _ToolButton({
    required this.icon,
    this.iconColor,
    this.selected = false,
    required this.onTap,
    this.onLongPress,
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
              onLongPress: onLongPress,
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

/// A plain, read-only render of a frame used during playback - deliberately
/// not the interactive [DrawingCanvas], so the camera transform only ever
/// moves the drawn content within a fixed, clipped viewport, rather than
/// also carrying along the drawing canvas's own internal zoom/clip layers.
class _PlaybackPreview extends StatelessWidget {
  final List<LayerFrameContent> contents;
  final CameraState? camera;

  const _PlaybackPreview({required this.contents, this.camera});

  @override
  Widget build(BuildContext context) {
    final artwork = Container(
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final content in contents)
            Stack(
              fit: StackFit.expand,
              children: [
                if (content.imagePath != null)
                  Opacity(
                    opacity: content.opacity,
                    child: Image.file(
                      File(ReferenceAssetService().fullPathFor(content.imagePath!)),
                      fit: BoxFit.cover,
                      // Without this, Image briefly shows nothing (revealing
                      // the white backdrop) every time the file changes,
                      // even though it's precached - the old frame should
                      // stay up until the new one is ready to paint.
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                    ),
                  ),
                CustomPaint(painter: FramePainter(strokes: content.strokes, opacity: content.opacity)),
              ],
            ),
        ],
      ),
    );

    if (camera == null) return ClipRect(child: artwork);

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final cam = camera!;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(cam.x * size.width, cam.y * size.height)
              ..rotateZ(cam.rotation)
              ..scale(cam.zoom),
            child: artwork,
          );
        },
      ),
    );
  }
}
