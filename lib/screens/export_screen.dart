import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/export_service.dart';
import '../models/export_checklist.dart';
import '../models/shot.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

enum _ResolutionTier { p1080, p720 }

enum _FpsChoice { matchShot, fps12, fps24 }

class ExportScreen extends StatefulWidget {
  final String projectId;
  final String episodeId;
  final String shotId;

  const ExportScreen({
    super.key,
    required this.projectId,
    required this.episodeId,
    required this.shotId,
  });

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final ExportService _exportService = ExportService();

  late CanvasOrientation _targetOrientation;
  _ResolutionTier _resolution = _ResolutionTier.p1080;
  _FpsChoice _fpsChoice = _FpsChoice.matchShot;

  bool _isExporting = false;
  double _exportProgress = 0;
  String? _exportedPath;
  bool _exportedAudio = false;
  String? _error;
  DateTime? _exportStartedAt;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    final shot = context.read<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId);
    _targetOrientation = shot?.orientation ?? CanvasOrientation.landscape;
  }

  (int, int) _targetSize() {
    final isLandscape = _targetOrientation == CanvasOrientation.landscape;
    final short = _resolution == _ResolutionTier.p1080 ? 1080 : 720;
    final long = _resolution == _ResolutionTier.p1080 ? 1920 : 1280;
    return isLandscape ? (long, short) : (short, long);
  }

  int _targetFps(Shot shot) {
    switch (_fpsChoice) {
      case _FpsChoice.matchShot:
        return shot.fps;
      case _FpsChoice.fps12:
        return 12;
      case _FpsChoice.fps24:
        return 24;
    }
  }

  Future<void> _runExport(Shot shot) async {
    setState(() {
      _isExporting = true;
      _exportProgress = 0;
      _error = null;
      _exportedPath = null;
      _exportStartedAt = DateTime.now();
      _cancelRequested = false;
    });
    try {
      final (width, height) = _targetSize();
      final result = await _exportService.exportShotVideo(
        shot: shot,
        width: width,
        height: height,
        fps: _targetFps(shot),
        onProgress: (p) {
          if (mounted) setState(() => _exportProgress = p);
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      await context.read<AppState>().recordExport(widget.projectId, widget.episodeId, widget.shotId);
      setState(() {
        _isExporting = false;
        _exportedPath = result.path;
        _exportedAudio = result.audioIncluded;
      });
    } on ExportCancelledException {
      if (!mounted) return;
      setState(() => _isExporting = false);
    } on NoExportableContentException catch (e) {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _error = e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _error = 'Export failed: $e';
      });
    }
  }

  void _cancelExport() {
    setState(() => _cancelRequested = true);
  }

  /// A rough ETA from elapsed time and progress so far - frame rendering
  /// speed varies a lot by device/resolution, so this is an estimate that
  /// settles down after the first few frames, not a precise countdown.
  String? _estimateRemaining() {
    final startedAt = _exportStartedAt;
    if (startedAt == null || _exportProgress <= 0.02) return null;
    final elapsed = DateTime.now().difference(startedAt);
    final totalEstimate = elapsed * (1 / _exportProgress);
    final remaining = totalEstimate - elapsed;
    if (remaining.inSeconds < 1) return 'almost done';
    if (remaining.inMinutes < 1) return '~${remaining.inSeconds}s left';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '~${minutes}m ${seconds}s left';
  }

  Future<void> _share(String path) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'Exported from Scribbled Angel Studio'));
  }

  @override
  Widget build(BuildContext context) {
    final shot = context.watch<AppState>().getShot(widget.projectId, widget.episodeId, widget.shotId);
    if (shot == null) {
      return const Scaffold(body: Center(child: Text('Shot not found')));
    }
    final checklist = shot.exportChecklist;
    final (width, height) = _targetSize();

    return Scaffold(
      appBar: AppBar(title: Text('Export · ${shot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Format', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SegmentedButton<CanvasOrientation>(
            segments: const [
              ButtonSegment(value: CanvasOrientation.landscape, label: Text('16:9 YouTube')),
              ButtonSegment(value: CanvasOrientation.portrait, label: Text('9:16 Shorts')),
            ],
            selected: {_targetOrientation},
            onSelectionChanged: _isExporting ? null : (s) => setState(() => _targetOrientation = s.first),
          ),
          const SizedBox(height: 10),
          SegmentedButton<_ResolutionTier>(
            segments: const [
              ButtonSegment(value: _ResolutionTier.p1080, label: Text('1080p')),
              ButtonSegment(value: _ResolutionTier.p720, label: Text('720p')),
            ],
            selected: {_resolution},
            onSelectionChanged: _isExporting ? null : (s) => setState(() => _resolution = s.first),
          ),
          const SizedBox(height: 10),
          SegmentedButton<_FpsChoice>(
            segments: [
              ButtonSegment(value: _FpsChoice.matchShot, label: Text('Shot FPS (${shot.fps})')),
              const ButtonSegment(value: _FpsChoice.fps12, label: Text('12 fps')),
              const ButtonSegment(value: _FpsChoice.fps24, label: Text('24 fps')),
            ],
            selected: {_fpsChoice},
            onSelectionChanged: _isExporting ? null : (s) => setState(() => _fpsChoice = s.first),
          ),
          const SizedBox(height: 6),
          Builder(builder: (context) {
            final fps = _targetFps(shot);
            final hasAudio = shot.audioClip != null && shot.audioClip!.effectiveDuration > 0;
            final audioSupported = pickAudioSampleRate(fps) != null;
            final String audioNote;
            if (!hasAudio) {
              audioNote = 'no audio set on this shot';
            } else if (!audioSupported) {
              audioNote = "this shot's audio won't be included - $fps fps has no exportable audio rate, try 12 or 24 fps";
            } else {
              audioNote = "this shot's audio will be included";
            }
            return Text(
              'Will export at ${width}x$height - $audioNote.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            );
          }),
          const SizedBox(height: 24),
          const Text('Before you publish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _ChecklistTile(label: 'Video', done: checklist.video, onChanged: null, hint: 'Checked automatically after export'),
          _ChecklistTile(
            label: 'Audio',
            done: checklist.audio,
            onChanged: (v) => context
                .read<AppState>()
                .updateExportChecklist(widget.projectId, widget.episodeId, widget.shotId, audio: v),
          ),
          _ChecklistTile(
            label: 'Thumbnail',
            done: checklist.thumbnail,
            onChanged: (v) => context
                .read<AppState>()
                .updateExportChecklist(widget.projectId, widget.episodeId, widget.shotId, thumbnail: v),
          ),
          _ChecklistTile(
            label: 'Title',
            done: checklist.title,
            onChanged: (v) =>
                context.read<AppState>().updateExportChecklist(widget.projectId, widget.episodeId, widget.shotId, title: v),
          ),
          _ChecklistTile(
            label: 'Description',
            done: checklist.description,
            onChanged: (v) => context
                .read<AppState>()
                .updateExportChecklist(widget.projectId, widget.episodeId, widget.shotId, description: v),
          ),
          _ChecklistTile(
            label: 'Subtitles',
            done: checklist.subtitles,
            onChanged: (v) => context
                .read<AppState>()
                .updateExportChecklist(widget.projectId, widget.episodeId, widget.shotId, subtitles: v),
          ),
          const SizedBox(height: 24),
          if (!shot.hasExportableContent)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No exportable artwork yet - every layer is empty or marked as a reference layer. '
                      'Draw on a Render layer, or switch one to Render, before exporting.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          if (_isExporting) ...[
            LinearProgressIndicator(value: _exportProgress),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final eta = _estimateRemaining();
              final percent = '${(_exportProgress * 100).round()}%';
              return Text(
                _cancelRequested
                    ? 'Cancelling…'
                    : (eta == null ? 'Rendering… $percent' : 'Rendering… $percent - $eta'),
                textAlign: TextAlign.center,
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _cancelRequested ? null : _cancelExport,
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 16),
          ] else ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.movie_creation_outlined),
              label: const Text('Export video'),
              onPressed: shot.hasExportableContent ? () => _runExport(shot) : null,
            ),
          ],
          if (_exportedPath != null) ...[
            const SizedBox(height: 16),
            Text(
              _exportedAudio ? 'Exported with audio.' : 'Exported - video only, no audio.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share / Save video'),
              onPressed: () => _share(_exportedPath!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  final String label;
  final bool done;
  final ValueChanged<bool>? onChanged;
  final String? hint;

  const _ChecklistTile({required this.label, required this.done, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: done,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      title: Text(label),
      subtitle: hint != null ? Text(hint!, style: const TextStyle(fontSize: 11)) : null,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }
}
