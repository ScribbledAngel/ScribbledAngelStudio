import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_service.dart';
import 'reference_asset_service.dart';
import '../models/camera_state.dart';
import '../models/layer_frame_content.dart';
import '../models/shot.dart';
import '../widgets/frame_painter.dart';

/// Standard sample rates Android's hardware AAC encoder actually supports -
/// an arbitrary rate fails encoder setup outright. Checked loudest-first so
/// audio quality is as good as the frame rate allows.
const List<int> _standardAacSampleRates = [48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000];

/// Finds a standard AAC sample rate that divides evenly by [fps] - every
/// `appendAudioFrame` call must carry an exact, fixed number of samples (one
/// video frame's worth), so the rate and the frame rate must divide evenly.
/// Returns null for frame rates with no evenly-dividing standard rate (a
/// handful of odd values like 11, 13, 17...) - those shots export video-only.
int? pickAudioSampleRate(int fps) {
  if (fps <= 0) return null;
  for (final rate in _standardAacSampleRates) {
    if (rate % fps == 0) return rate;
  }
  return null;
}

/// Thrown when a shot has no Render-layer content to export - every layer
/// is either empty or Reference-only. Caught by the export screen to show
/// a clear warning instead of silently producing a blank video.
class NoExportableContentException implements Exception {
  const NoExportableContentException();

  @override
  String toString() =>
      'This shot has no exportable artwork - every layer is empty or marked as a reference layer.';
}

/// Thrown when the user cancels an in-progress export.
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => 'Export cancelled.';
}

/// The result of a successful export - the output file, plus whether the
/// shot's audio actually made it in (so the UI can say so if it didn't).
class ExportResult {
  final String path;
  final bool audioIncluded;

  const ExportResult({required this.path, required this.audioIncluded});
}

/// Renders a shot's frames (plus its camera move, if any) to a local MP4
/// file using the device's own hardware video encoder - no FFmpeg, no
/// upload, just a file written to the app's export folder.
///
/// Only Render-type, visible layers are included (see [Shot.exportLayerContentsAt])
/// - Reference layers never appear in the output, regardless of their
/// editor visibility. The shot's own audio (trim/volume applied) is decoded
/// to raw PCM and muxed in alongside the video, when the shot's frame rate
/// has a standard AAC sample rate that divides evenly into it (see
/// [pickAudioSampleRate]) - a handful of odd frame rates export video-only.
class ExportService {
  final ReferenceAssetService _referenceAssets = ReferenceAssetService();
  final AudioService _audioService = AudioService();

  Future<Directory> _exportDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<ExportResult> exportShotVideo({
    required Shot shot,
    required int width,
    required int height,
    required int fps,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!shot.hasExportableContent) {
      throw const NoExportableContentException();
    }

    final dir = await _exportDir();
    final safeName = shot.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final outputPath = '${dir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final totalFrames = shot.frameCount;
    final durationSeconds = shot.durationSeconds;
    final totalExportFrames = (durationSeconds * fps).round().clamp(1, 1 << 30).toInt();

    final audio = await _prepareAudio(shot, fps: fps, totalExportFrames: totalExportFrames);

    await FlutterQuickVideoEncoder.setup(
      width: width,
      height: height,
      fps: fps,
      videoBitrate: 6 * 1000 * 1000,
      profileLevel: ProfileLevel.any,
      audioChannels: audio == null ? 0 : 1,
      audioBitrate: audio == null ? 0 : 128 * 1000,
      sampleRate: audio?.sampleRate ?? 0,
      filepath: outputPath,
    );

    try {
      try {
        final sourceWidth = shot.canvasWidthPx ?? width.toDouble();
        final sourceHeight = shot.canvasHeightPx ?? height.toDouble();

        final imageCache = await _preloadImages(shot);

        for (var i = 0; i < totalExportFrames; i++) {
          if (isCancelled?.call() ?? false) {
            throw const ExportCancelledException();
          }
          final sourceTime = i / fps;
          final sourceIndex = (sourceTime * shot.fps).floor().clamp(0, totalFrames - 1).toInt();
          final contents = shot.exportLayerContentsAt(sourceIndex);

          CameraState? camera;
          if (shot.cameraMoveEnabled && totalFrames > 1) {
            final t = sourceIndex / (totalFrames - 1);
            camera = CameraState.lerp(shot.cameraStart, shot.cameraEnd, t);
          }

          final bytes = await _renderFrameRgba(
            contents: contents,
            imageCache: imageCache,
            exportWidth: width,
            exportHeight: height,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            camera: camera,
          );
          await FlutterQuickVideoEncoder.appendVideoFrame(bytes);

          if (audio != null) {
            final startSample = i * audio.samplesPerFrame;
            final frameBytes = audio.samples.buffer.asUint8List(startSample * 2, audio.samplesPerFrame * 2);
            await FlutterQuickVideoEncoder.appendAudioFrame(frameBytes);
          }

          onProgress?.call((i + 1) / totalExportFrames);
        }
      } finally {
        await FlutterQuickVideoEncoder.finish();
      }
    } on ExportCancelledException {
      final partialFile = File(outputPath);
      if (await partialFile.exists()) await partialFile.delete();
      rethrow;
    }

    return ExportResult(path: outputPath, audioIncluded: audio != null);
  }

  /// Decodes the shot's audio clip (its trim range, with volume applied)
  /// into mono PCM at a sample rate that divides evenly into [fps], padded
  /// or truncated with silence to exactly match the video's length. Returns
  /// null if the shot has no audio, the frame rate has no usable sample
  /// rate, or decoding fails - any of which just means "export without
  /// audio" rather than failing the whole export.
  Future<_PreparedAudio?> _prepareAudio(Shot shot, {required int fps, required int totalExportFrames}) async {
    final clip = shot.audioClip;
    if (clip == null || clip.effectiveDuration <= 0) return null;

    final sampleRate = pickAudioSampleRate(fps);
    if (sampleRate == null) return null;

    final decoded = await _audioService.decodePcmForExport(
      fileName: clip.fileName,
      startSeconds: clip.trimStart,
      endSeconds: clip.trimEnd,
    );
    if (decoded == null || decoded.sampleRate <= 0 || decoded.channelCount <= 0) return null;

    final samplesPerFrame = sampleRate ~/ fps;
    final totalSamples = samplesPerFrame * totalExportFrames;

    final mono = _downmixToMono(decoded.bytes, decoded.channelCount);
    final resampled = _resample(mono, decoded.sampleRate, sampleRate);

    final samples = Int16List(totalSamples);
    final copyCount = resampled.length < totalSamples ? resampled.length : totalSamples;
    for (var i = 0; i < copyCount; i++) {
      samples[i] = (resampled[i] * clip.volume).round().clamp(-32768, 32767);
    }
    // Any remaining samples (resampled audio shorter than the video) stay
    // zero - silence - from Int16List's default initialization.

    return _PreparedAudio(samples: samples, sampleRate: sampleRate, samplesPerFrame: samplesPerFrame);
  }

  /// Averages interleaved 16-bit PCM channels down to mono.
  Int16List _downmixToMono(Uint8List rawPcm, int channelCount) {
    final byteData = ByteData.sublistView(rawPcm);
    final frameCount = rawPcm.length ~/ (2 * channelCount);
    final mono = Int16List(frameCount);
    for (var i = 0; i < frameCount; i++) {
      var sum = 0;
      for (var c = 0; c < channelCount; c++) {
        sum += byteData.getInt16((i * channelCount + c) * 2, Endian.little);
      }
      mono[i] = (sum / channelCount).round().clamp(-32768, 32767);
    }
    return mono;
  }

  /// Simple linear-interpolation resampler - adequate for voiceover/sync
  /// reference audio, which is this app's only use case for exported audio.
  Int16List _resample(Int16List samples, int fromRate, int toRate) {
    if (fromRate == toRate || samples.isEmpty) return samples;
    final outLength = (samples.length * toRate / fromRate).round();
    final out = Int16List(outLength);
    final ratio = fromRate / toRate;
    for (var i = 0; i < outLength; i++) {
      final srcPos = i * ratio;
      final srcIndex = srcPos.floor();
      final frac = srcPos - srcIndex;
      final a = samples[srcIndex.clamp(0, samples.length - 1)];
      final b = samples[(srcIndex + 1).clamp(0, samples.length - 1)];
      out[i] = (a + (b - a) * frac).round().clamp(-32768, 32767);
    }
    return out;
  }

  /// Decodes every unique reference image used by a Render layer up front,
  /// since CustomPainter.paint is synchronous but image decoding isn't.
  /// Reference-layer images are never decoded here - they're excluded from
  /// export entirely, so there's no point loading them.
  Future<Map<String, ui.Image>> _preloadImages(Shot shot) async {
    final cache = <String, ui.Image>{};
    for (var i = 0; i < shot.frameCount; i++) {
      for (final content in shot.exportLayerContentsAt(i)) {
        final path = content.imagePath;
        if (path == null || cache.containsKey(path)) continue;
        try {
          final bytes = await File(_referenceAssets.fullPathFor(path)).readAsBytes();
          cache[path] = await decodeImageFromList(bytes);
        } catch (_) {
          // Missing/corrupt reference image - just skip it for this frame
          // rather than failing the whole export.
        }
      }
    }
    return cache;
  }

  Future<Uint8List> _renderFrameRgba({
    required List<LayerFrameContent> contents,
    required Map<String, ui.Image> imageCache,
    required int exportWidth,
    required int exportHeight,
    required double sourceWidth,
    required double sourceHeight,
    CameraState? camera,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = exportWidth.toDouble();
    final h = exportHeight.toDouble();

    // MP4/H.264 has no alpha channel, so there's no transparent-background
    // option to preserve here - fill with white, same as the live editor.
    canvas.drawRect(Offset.zero & Size(w, h), Paint()..color = Colors.white);

    canvas.save();
    if (camera != null) {
      canvas.translate(w / 2, h / 2);
      canvas.translate(camera.x * w, camera.y * h);
      canvas.rotate(camera.rotation);
      canvas.scale(camera.zoom);
      canvas.translate(-w / 2, -h / 2);
    }
    // Strokes/images are stored in the drawing canvas's original screen
    // coordinates - scale them up/down onto the export resolution.
    if (sourceWidth > 0 && sourceHeight > 0) {
      canvas.scale(w / sourceWidth, h / sourceHeight);
    }
    final sourceRect = Rect.fromLTWH(0, 0, sourceWidth, sourceHeight);
    for (final content in contents) {
      final image = content.imagePath == null ? null : imageCache[content.imagePath];
      if (image != null) {
        final paint = Paint()..color = Colors.white.withOpacity(content.opacity);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          sourceRect,
          paint,
        );
      }
      FramePainter(strokes: content.strokes, opacity: content.opacity).paint(canvas, Size(sourceWidth, sourceHeight));
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(exportWidth, exportHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }
}

/// Mono PCM ready to feed to the encoder one video-frame's worth at a time.
class _PreparedAudio {
  final Int16List samples;
  final int sampleRate;
  final int samplesPerFrame;

  const _PreparedAudio({required this.samples, required this.sampleRate, required this.samplesPerFrame});
}
