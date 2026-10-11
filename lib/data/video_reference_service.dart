import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'app_storage.dart';
import 'audio_service.dart';
import 'reference_asset_service.dart';

const _uuid = Uuid();

class VideoExtractionResult {
  final List<String> frameImagePaths;
  final String? audioFileName;

  VideoExtractionResult({required this.frameImagePaths, this.audioFileName});
}

/// Imports a video, extracts a snippet of it as a frame sequence (for
/// rotoscoping reference layers) plus its audio track, using the device's
/// own decoders - no FFmpeg anywhere in this pipeline.
class VideoReferenceService {
  static const _audioChannel = MethodChannel(
    'com.scribbledangelstudio.scribbled_angel_studio/audio_extractor',
  );

  Future<Directory> _videosDir() async {
    final dir = Directory('${AppStorage.documentsPath}/reference_videos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String fullVideoPathFor(String fileName) => '${AppStorage.documentsPath}/reference_videos/$fileName';

  /// Lets the user pick a video file and copies it into the app's private
  /// storage, returning the new file's bare name. Duration is probed by the
  /// caller via VideoPlayerController, which the trim screen needs for
  /// playback/preview anyway - video_thumbnail doesn't report it.
  Future<String?> importVideo() async {
    final picked = await FilePicker.pickFile(type: FileType.video);
    final pickedPath = picked?.path;
    if (pickedPath == null) return null;

    final extension = pickedPath.contains('.') ? pickedPath.split('.').last : 'mp4';
    final fileName = '${_uuid.v4()}.$extension';
    final dir = await _videosDir();
    await File(pickedPath).copy('${dir.path}/$fileName');
    return fileName;
  }

  /// Extracts frames across [snippetStart]..[snippetEnd] (seconds into the
  /// source video) at [extractionFps], plus the corresponding audio if any,
  /// reporting progress from 0 to 1.
  Future<VideoExtractionResult> extractSnippet({
    required String videoFileName,
    required double snippetStart,
    required double snippetEnd,
    required double extractionFps,
    void Function(double progress)? onProgress,
  }) async {
    final videoPath = fullVideoPathFor(videoFileName);
    final referenceAssets = ReferenceAssetService();
    await referenceAssets.ensureImagesDir();

    final durationSeconds = (snippetEnd - snippetStart).clamp(0, double.infinity);
    final frameCount = (durationSeconds * extractionFps).round().clamp(1, 1 << 20);

    final framePaths = <String>[];
    for (var i = 0; i < frameCount; i++) {
      final timeSeconds = snippetStart + (i / extractionFps);
      final timeMs = (timeSeconds * 1000).round();
      // video_thumbnail derives its own filename from the SOURCE VIDEO's
      // name when given a bare directory - since every call here shares the
      // same source video, every frame would collide on the same output
      // path. Passing a full file path (ending in the target extension)
      // makes it use that exact path instead, with no derivation at all.
      final finalFileName = '${_uuid.v4()}.png';
      final finalPath = referenceAssets.fullPathFor(finalFileName);
      try {
        final writtenPath = await vt.VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: finalPath,
          imageFormat: vt.ImageFormat.PNG,
          maxWidth: 1280,
          timeMs: timeMs,
          quality: 90,
        );
        if (writtenPath != null) framePaths.add(finalFileName);
      } catch (_) {
        // Skip this one frame rather than failing the whole extraction.
      }

      onProgress?.call((i + 1) / frameCount);
    }

    final audioFileName = await _extractAudio(videoPath, snippetStart, snippetEnd);
    return VideoExtractionResult(frameImagePaths: framePaths, audioFileName: audioFileName);
  }

  Future<String?> _extractAudio(String videoPath, double snippetStart, double snippetEnd) async {
    // Written directly into AudioService's own `audio/` folder (not our
    // `reference_videos/` folder) - this makes it usable with the shot's
    // existing audio playback, trim and volume controls, which only ever
    // look for files there via AudioService.fullPathFor.
    final fileName = '${_uuid.v4()}.m4a';
    final outputPath = await AudioService().fullPathFor(fileName);
    try {
      final extracted = await _audioChannel.invokeMethod<bool>('extractAudio', {
        'sourcePath': videoPath,
        'outputPath': outputPath,
        'startMs': (snippetStart * 1000).round(),
        'endMs': (snippetEnd * 1000).round(),
      });
      if (extracted != true) return null;
      return fileName;
    } catch (_) {
      return null;
    }
  }

  /// Decodes the video's audio track and returns [sampleCount] peak
  /// amplitudes (0.0-1.0) spanning its full duration, for drawing a
  /// waveform under the trim slider. Returns null if there's no audio.
  Future<List<double>?> extractWaveformPeaks({
    required String videoFileName,
    required double durationSeconds,
    int sampleCount = 200,
  }) async {
    final videoPath = fullVideoPathFor(videoFileName);
    try {
      final peaks = await _audioChannel.invokeMethod<List<dynamic>>('extractWaveformPeaks', {
        'sourcePath': videoPath,
        'startMs': 0,
        'endMs': (durationSeconds * 1000).round(),
        'sampleCount': sampleCount,
      });
      return peaks?.map((p) => (p as num).toDouble()).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteVideo(String fileName) async {
    final file = File(fullVideoPathFor(fileName));
    if (await file.exists()) await file.delete();
  }
}
