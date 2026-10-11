import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:path_provider/path_provider.dart';

import 'reference_asset_service.dart';
import '../models/camera_state.dart';
import '../models/layer_frame_content.dart';
import '../models/shot.dart';
import '../widgets/frame_painter.dart';

/// Thrown when a shot has no Render-layer content to export - every layer
/// is either empty or Reference-only. Caught by the export screen to show
/// a clear warning instead of silently producing a blank video.
class NoExportableContentException implements Exception {
  const NoExportableContentException();

  @override
  String toString() =>
      'This shot has no exportable artwork - every layer is empty or marked as a reference layer.';
}

/// Renders a shot's frames (plus its camera move, if any) to a local MP4
/// file using the device's own hardware video encoder - no FFmpeg, no
/// upload, just a file written to the app's export folder.
///
/// Only Render-type, visible layers are included (see [Shot.exportLayerContentsAt])
/// - Reference layers never appear in the output, regardless of their
/// editor visibility. Video only for now - muxing the shot's own
/// recorded/imported audio would mean decoding it to raw PCM first, which
/// is a reasonable next step but out of scope for this pass.
class ExportService {
  final ReferenceAssetService _referenceAssets = ReferenceAssetService();

  Future<Directory> _exportDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> exportShotVideo({
    required Shot shot,
    required int width,
    required int height,
    required int fps,
    void Function(double progress)? onProgress,
  }) async {
    if (!shot.hasExportableContent) {
      throw const NoExportableContentException();
    }

    final dir = await _exportDir();
    final safeName = shot.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final outputPath = '${dir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.mp4';

    await FlutterQuickVideoEncoder.setup(
      width: width,
      height: height,
      fps: fps,
      videoBitrate: 6 * 1000 * 1000,
      profileLevel: ProfileLevel.any,
      audioChannels: 0,
      audioBitrate: 0,
      sampleRate: 0,
      filepath: outputPath,
    );

    try {
      final sourceWidth = shot.canvasWidthPx ?? width.toDouble();
      final sourceHeight = shot.canvasHeightPx ?? height.toDouble();
      final totalFrames = shot.frameCount;
      final durationSeconds = shot.durationSeconds;
      final totalExportFrames = (durationSeconds * fps).round().clamp(1, 1 << 30).toInt();

      final imageCache = await _preloadImages(shot);

      for (var i = 0; i < totalExportFrames; i++) {
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
        onProgress?.call((i + 1) / totalExportFrames);
      }
    } finally {
      await FlutterQuickVideoEncoder.finish();
    }

    return outputPath;
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
