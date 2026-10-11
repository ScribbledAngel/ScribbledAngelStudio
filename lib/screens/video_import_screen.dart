import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../data/video_reference_service.dart';
import '../models/audio_clip.dart';
import '../models/video_reference_source.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/prompt_dialog.dart';

const _uuid = Uuid();

enum _FpsChoice { fps4, fps8, fps12, fps24 }

extension on _FpsChoice {
  double get value {
    switch (this) {
      case _FpsChoice.fps4:
        return 4;
      case _FpsChoice.fps8:
        return 8;
      case _FpsChoice.fps12:
        return 12;
      case _FpsChoice.fps24:
        return 24;
    }
  }
}

/// Import a video, pick a snippet and extraction rate, and turn it into a
/// Reference layer (plus its extracted audio, if any) on the current shot.
class VideoImportScreen extends StatefulWidget {
  final String projectId;
  final String episodeId;
  final String shotId;

  const VideoImportScreen({
    super.key,
    required this.projectId,
    required this.episodeId,
    required this.shotId,
  });

  @override
  State<VideoImportScreen> createState() => _VideoImportScreenState();
}

class _VideoImportScreenState extends State<VideoImportScreen> {
  final VideoReferenceService _service = VideoReferenceService();
  VideoPlayerController? _controller;
  String? _videoFileName;

  bool _isLoadingVideo = true;
  bool _isExtracting = false;
  double _extractProgress = 0;
  String? _error;

  double _snippetStart = 0;
  double _snippetEnd = 1;
  _FpsChoice _fpsChoice = _FpsChoice.fps8;

  Uint8List? _startThumb;
  Uint8List? _endThumb;
  int _thumbRequestId = 0;

  List<double>? _waveformPeaks;
  bool _isLoadingWaveform = false;

  @override
  void initState() {
    super.initState();
    _pickAndLoadVideo();
  }

  @override
  void dispose() {
    _controller?.removeListener(_loopWithinSnippet);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickAndLoadVideo() async {
    final fileName = await _service.importVideo();
    if (!mounted) return;
    if (fileName == null) {
      Navigator.of(context).pop();
      return;
    }
    final controller = VideoPlayerController.file(File(_service.fullVideoPathFor(fileName)));
    try {
      await controller.initialize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingVideo = false;
        _error = 'Could not read this video: $e';
      });
      return;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    final durationSeconds = controller.value.duration.inMilliseconds / 1000.0;
    controller.addListener(_loopWithinSnippet);
    setState(() {
      _videoFileName = fileName;
      _controller = controller;
      _isLoadingVideo = false;
      _snippetStart = 0;
      _snippetEnd = durationSeconds.clamp(0.1, 10.0); // default to a short snippet, not the whole clip
    });
    await controller.seekTo(Duration.zero);
    _refreshBoundaryThumbnails();
    _loadWaveform(fileName, durationSeconds);
  }

  /// Decodes the whole clip's audio once into peak amplitudes, so the
  /// waveform can be drawn under the trim slider - a more reliable way to
  /// find sync points than scrubbing/listening to playback alone.
  Future<void> _loadWaveform(String fileName, double durationSeconds) async {
    if (durationSeconds <= 0) return;
    setState(() => _isLoadingWaveform = true);
    final peaks = await _service.extractWaveformPeaks(
      videoFileName: fileName,
      durationSeconds: durationSeconds,
    );
    if (!mounted) return;
    setState(() {
      _waveformPeaks = peaks;
      _isLoadingWaveform = false;
    });
  }

  /// Keeps playback looping within the selected snippet only, so what you
  /// see previewed is exactly what will be extracted - not the whole video.
  void _loopWithinSnippet() {
    final controller = _controller;
    if (controller == null || !controller.value.isPlaying) return;
    final positionSeconds = controller.value.position.inMilliseconds / 1000.0;
    if (positionSeconds >= _snippetEnd) {
      controller.seekTo(Duration(milliseconds: (_snippetStart * 1000).round()));
    }
  }

  Future<void> _refreshBoundaryThumbnails() async {
    final fileName = _videoFileName;
    if (fileName == null) return;
    final requestId = ++_thumbRequestId;
    final videoPath = _service.fullVideoPathFor(fileName);
    final startMs = (_snippetStart * 1000).round();
    final endMs = (_snippetEnd * 1000).round();

    final start = await vt.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: vt.ImageFormat.JPEG,
      maxWidth: 300,
      timeMs: startMs,
      quality: 75,
    ).catchError((_) => null);
    final end = await vt.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: vt.ImageFormat.JPEG,
      maxWidth: 300,
      timeMs: endMs,
      quality: 75,
    ).catchError((_) => null);

    if (!mounted || requestId != _thumbRequestId) return; // a newer request superseded this one
    setState(() {
      _startThumb = start;
      _endThumb = end;
    });
  }

  Future<void> _extract() async {
    final fileName = _videoFileName;
    if (fileName == null) return;
    setState(() {
      _isExtracting = true;
      _extractProgress = 0;
      _error = null;
    });
    try {
      final result = await _service.extractSnippet(
        videoFileName: fileName,
        snippetStart: _snippetStart,
        snippetEnd: _snippetEnd,
        extractionFps: _fpsChoice.value,
        onProgress: (p) {
          if (mounted) setState(() => _extractProgress = p);
        },
      );
      if (result.frameImagePaths.isEmpty) {
        throw Exception('No frames could be extracted from this clip.');
      }
      if (!mounted) return;
      final appState = context.read<AppState>();
      await appState.addVideoReferenceLayer(
        widget.projectId,
        widget.episodeId,
        widget.shotId,
        frameImagePaths: result.frameImagePaths,
        videoSource: VideoReferenceSource(
          sourceVideoFileName: fileName,
          audioFileName: result.audioFileName,
          snippetStart: _snippetStart,
          snippetEnd: _snippetEnd,
          extractionFps: _fpsChoice.value,
        ),
      );
      if (!mounted) return;

      if (result.audioFileName != null) {
        final shot = appState.getShot(widget.projectId, widget.episodeId, widget.shotId);
        var useExtractedAudio = true;
        if (shot?.audioClip != null) {
          useExtractedAudio = await showConfirmDialog(
            context,
            title: 'Use this clip\'s audio?',
            message: 'This shot already has audio set. Replace it with the audio extracted from this video?',
            confirmLabel: 'Replace',
            isDanger: false,
          );
        }
        if (useExtractedAudio && mounted) {
          await appState.setShotAudio(
            widget.projectId,
            widget.episodeId,
            widget.shotId,
            AudioClip(
              id: _uuid.v4(),
              fileName: result.audioFileName!,
              sourceDurationSeconds: _snippetEnd - _snippetStart,
            ),
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExtracting = false;
        _error = 'Extraction failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video reference')),
      body: _isLoadingVideo
          ? const Center(child: CircularProgressIndicator())
          : _controller == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error ?? 'Could not load this video.', textAlign: TextAlign.center),
                  ),
                )
              : _buildTrimUi(),
    );
  }

  Widget _buildTrimUi() {
    final controller = _controller!;
    final durationSeconds = controller.value.duration.inMilliseconds / 1000.0;
    final frameCount = ((_snippetEnd - _snippetStart) * _fpsChoice.value).round().clamp(0, 1 << 20);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                IconButton(
                  iconSize: 48,
                  color: Colors.white,
                  icon: Icon(
                    controller.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                  ),
                  onPressed: () => setState(() {
                    if (controller.value.isPlaying) {
                      controller.pause();
                    } else {
                      // Always start playback from the snippet's beginning,
                      // so what loops is exactly what will be extracted.
                      controller.seekTo(Duration(milliseconds: (_snippetStart * 1000).round()));
                      controller.play();
                    }
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Preview loops only the selected snippet below.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _BoundaryThumbnail(label: 'First frame', bytes: _startThumb)),
            const SizedBox(width: 12),
            Expanded(child: _BoundaryThumbnail(label: 'Last frame', bytes: _endThumb)),
          ],
        ),
        const SizedBox(height: 16),
        Text('Snippet: ${_snippetStart.toStringAsFixed(1)}s – ${_snippetEnd.toStringAsFixed(1)}s', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          width: double.infinity,
          child: _isLoadingWaveform
              ? const Center(
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : _waveformPeaks == null || _waveformPeaks!.isEmpty
                  ? Center(
                      child: Text(
                        'No audio to visualize',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _WaveformPainter(
                            peaks: _waveformPeaks!,
                            durationSeconds: durationSeconds,
                            rangeStart: _snippetStart,
                            rangeEnd: _snippetEnd,
                            playheadSeconds: controller.value.isPlaying
                                ? controller.value.position.inMilliseconds / 1000.0
                                : null,
                          ),
                          size: Size.infinite,
                        );
                      },
                    ),
        ),
        const SizedBox(height: 4),
        RangeSlider(
          min: 0,
          max: durationSeconds > 0 ? durationSeconds : 1,
          values: RangeValues(_snippetStart, _snippetEnd),
          onChanged: _isExtracting
              ? null
              : (values) {
                  setState(() {
                    _snippetStart = values.start;
                    _snippetEnd = values.end;
                  });
                  controller.seekTo(Duration(milliseconds: (values.start * 1000).round()));
                },
          onChangeEnd: _isExtracting ? null : (_) => _refreshBoundaryThumbnails(),
        ),
        const SizedBox(height: 8),
        const Text('Extraction rate', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<_FpsChoice>(
          segments: const [
            ButtonSegment(value: _FpsChoice.fps4, label: Text('4 fps')),
            ButtonSegment(value: _FpsChoice.fps8, label: Text('8 fps')),
            ButtonSegment(value: _FpsChoice.fps12, label: Text('12 fps')),
            ButtonSegment(value: _FpsChoice.fps24, label: Text('24 fps')),
          ],
          selected: {_fpsChoice},
          onSelectionChanged: _isExtracting ? null : (s) => setState(() => _fpsChoice = s.first),
        ),
        const SizedBox(height: 8),
        Text(
          'Will extract about $frameCount reference frame${frameCount == 1 ? '' : 's'} and the clip\'s audio, if any.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ),
        if (_isExtracting) ...[
          LinearProgressIndicator(value: _extractProgress),
          const SizedBox(height: 8),
          Text('Extracting… ${(_extractProgress * 100).round()}%', textAlign: TextAlign.center),
        ] else
          ElevatedButton.icon(
            icon: const Icon(Icons.movie_filter_outlined),
            label: const Text('Extract & create reference layer'),
            onPressed: _snippetEnd > _snippetStart ? _extract : null,
          ),
      ],
    );
  }
}

/// Draws peak amplitudes as vertical bars, with the currently-selected
/// snippet range highlighted and (while playing) a moving playhead line -
/// so the user can visually line up drawing/sync points with audio peaks
/// instead of relying on ear alone.
class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double durationSeconds;
  final double rangeStart;
  final double rangeEnd;
  final double? playheadSeconds;

  _WaveformPainter({
    required this.peaks,
    required this.durationSeconds,
    required this.rangeStart,
    required this.rangeEnd,
    this.playheadSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || durationSeconds <= 0) return;

    final rangeStartX = (rangeStart / durationSeconds) * size.width;
    final rangeEndX = (rangeEnd / durationSeconds) * size.width;
    canvas.drawRect(
      Rect.fromLTRB(rangeStartX, 0, rangeEndX, size.height),
      Paint()..color = AppColors.accent.withValues(alpha: 0.15),
    );

    final barWidth = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final barTimeSeconds = (i / peaks.length) * durationSeconds;
      final inRange = barTimeSeconds >= rangeStart && barTimeSeconds <= rangeEnd;
      final barHeight = (peaks[i] * size.height).clamp(2.0, size.height);
      final paint = Paint()..color = inRange ? AppColors.accent : AppColors.textSecondary.withValues(alpha: 0.5);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(i * barWidth + barWidth / 2, size.height / 2),
          width: (barWidth * 0.7).clamp(1.0, barWidth),
          height: barHeight,
        ),
        paint,
      );
    }

    final playhead = playheadSeconds;
    if (playhead != null) {
      final playheadX = (playhead / durationSeconds) * size.width;
      canvas.drawLine(
        Offset(playheadX, 0),
        Offset(playheadX, size.height),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks ||
        oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd ||
        oldDelegate.playheadSeconds != playheadSeconds;
  }
}

class _BoundaryThumbnail extends StatelessWidget {
  final String label;
  final Uint8List? bytes;

  const _BoundaryThumbnail({required this.label, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: AppColors.surfaceHigh,
              child: bytes == null
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Image.memory(bytes!, fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
