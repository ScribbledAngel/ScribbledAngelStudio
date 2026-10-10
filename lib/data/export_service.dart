import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:path_provider/path_provider.dart';

import '../models/camera_state.dart';
import '../models/shot.dart';
import '../models/stroke.dart';
import '../widgets/frame_painter.dart';

/// Renders a shot's frames (plus its camera move, if any) to a local MP4
/// file using the device's own hardware video encoder - no FFmpeg, no
/// upload, just a file written to the app's export folder.
///
/// Video only for now - muxing the shot's own recorded/imported audio would
/// mean decoding it to raw PCM first, which is a reasonable next step but
/// out of scope for this pass.
class ExportService {
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

      for (var i = 0; i < totalExportFrames; i++) {
        final sourceTime = i / fps;
        final sourceIndex = (sourceTime * shot.fps).floor().clamp(0, totalFrames - 1).toInt();
        final strokes = shot.compositeStrokesAt(sourceIndex);

        CameraState? camera;
        if (shot.cameraMoveEnabled && totalFrames > 1) {
          final t = sourceIndex / (totalFrames - 1);
          camera = CameraState.lerp(shot.cameraStart, shot.cameraEnd, t);
        }

        final bytes = await _renderFrameRgba(
          strokes: strokes,
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

  Future<Uint8List> _renderFrameRgba({
    required List<Stroke> strokes,
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

    canvas.drawRect(Offset.zero & Size(w, h), Paint()..color = Colors.white);

    canvas.save();
    if (camera != null) {
      canvas.translate(w / 2, h / 2);
      canvas.translate(camera.x * w, camera.y * h);
      canvas.rotate(camera.rotation);
      canvas.scale(camera.zoom);
      canvas.translate(-w / 2, -h / 2);
    }
    // Strokes are stored in the drawing canvas's original screen
    // coordinates - scale them up/down onto the export resolution.
    if (sourceWidth > 0 && sourceHeight > 0) {
      canvas.scale(w / sourceWidth, h / sourceHeight);
    }
    FramePainter(strokes: strokes).paint(canvas, Size(sourceWidth, sourceHeight));
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(exportWidth, exportHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }
}
