import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/audio_clip.dart';

const _uuid = Uuid();

/// Recording, importing and probing audio clips. Files live in a private
/// `audio/` folder inside the app's documents directory; [AudioClip] only
/// ever stores the bare file name, never a full path.
class AudioService {
  AudioRecorder? _recorder;

  Future<Directory> _audioDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/audio');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> fullPathFor(String fileName) async {
    final dir = await _audioDir();
    return '${dir.path}/$fileName';
  }

  Future<bool> requestPermission() async {
    _recorder ??= AudioRecorder();
    return _recorder!.hasPermission();
  }

  Future<bool> startRecording() async {
    if (!await requestPermission()) return false;
    final dir = await _audioDir();
    final path = '${dir.path}/${_uuid.v4()}.m4a';
    await _recorder!.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    return true;
  }

  /// Stops the in-progress recording and returns a ready-to-save [AudioClip],
  /// or null if nothing was recorded.
  Future<AudioClip?> stopRecording() async {
    final recorder = _recorder;
    if (recorder == null) return null;
    final path = await recorder.stop();
    if (path == null) return null;
    final duration = await _probeDuration(path);
    return AudioClip(
      id: _uuid.v4(),
      fileName: path.split(Platform.pathSeparator).last,
      sourceDurationSeconds: duration,
    );
  }

  Future<void> cancelRecording() async {
    await _recorder?.stop();
  }

  /// Lets the user pick an audio file from device storage, copies it into
  /// the app's private audio folder, and returns a ready-to-save [AudioClip].
  Future<AudioClip?> importAudioFile() async {
    final picked = await FilePicker.pickFile(type: FileType.audio);
    final pickedPath = picked?.path;
    if (pickedPath == null) return null;

    final extension = pickedPath.contains('.') ? pickedPath.split('.').last : 'm4a';
    final fileName = '${_uuid.v4()}.$extension';
    final destPath = await fullPathFor(fileName);
    await File(pickedPath).copy(destPath);

    final duration = await _probeDuration(destPath);
    return AudioClip(id: _uuid.v4(), fileName: fileName, sourceDurationSeconds: duration);
  }

  Future<double> _probeDuration(String path) async {
    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(path);
      return (duration?.inMilliseconds ?? 0) / 1000.0;
    } catch (_) {
      return 0;
    } finally {
      await player.dispose();
    }
  }

  Future<void> deleteFile(String fileName) async {
    final path = await fullPathFor(fileName);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
